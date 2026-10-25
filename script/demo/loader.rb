require "open3"
require_relative "documents"

# Fills an empty development database with the fictional demo library used
# for screenshots: a signed-in user, correspondents, types, tags, rules,
# documents made from HTML (PDFs, scanned PDFs and receipt photos), review
# items and saved Research conversations. Documents go through the real
# processing pipeline with AI off (embedded text and Tesseract), then get the
# details an AI provider would have proposed. Nothing is sent anywhere.
module Demo
  class Loader
    WORK_DIR = Rails.root.join("tmp/demo")
    EMAIL = "sam@example.com".freeze
    PASSWORD = "zeropaper-demo".freeze
    AI_MODEL = "gpt-5.6-luna".freeze

    TAG_COLORS = {
      "utilities" => "sky", "home" => "emerald", "insurance" => "amber", "car" => "orange", "bank" => "teal",
      "medical" => "red", "dental" => "pink", "taxes-2025" => "violet", "taxes-2026" => "indigo", "income" => "lime",
      "donations" => "lime", "appliances" => "slate", "receipts" => "slate", "pets" => "orange", "travel" => "sky"
    }.freeze

    def run
      abort "demo:load only runs in development." unless Rails.env.development?
      abort "The database already has users or documents. Start from an empty one: bin/rails db:drop db:create db:schema:load" if User.exists? || Document.exists?

      ActiveJob::Base.queue_adapter = :inline
      build_files
      create_user
      create_settings
      create_taxonomy
      create_rules
      documents = ingest_documents
      apply_details(documents)
      flag_duplicate(documents)
      turn_on_ai
      create_conversations(documents)
      SolidQueue::Job.delete_all
      puts "Demo library ready: #{Document.count} documents. Sign in as #{EMAIL} / #{PASSWORD}"
    end

    private
      def specs
        @specs ||= Documents.all
      end

      def build_files
        %w[html pdf files].each { |dir| FileUtils.rm_rf(WORK_DIR.join(dir)) && FileUtils.mkdir_p(WORK_DIR.join(dir)) }
        specs.each { |spec| File.write(WORK_DIR.join("html", "#{spec.key}.html"), spec.html) }
        run!("node", Rails.root.join("script/demo/render.js").to_s, WORK_DIR.join("html").to_s, WORK_DIR.join("pdf").to_s)

        specs.each do |spec|
          pdf = WORK_DIR.join("pdf", "#{spec.key}.pdf").to_s
          target = WORK_DIR.join("files", spec.filename).to_s
          case spec.format
          when :pdf then FileUtils.cp(pdf, target)
          when :scan_pdf then scan_pdf(spec, pdf, target)
          when :scan_jpg then photo(spec, pdf, target)
          end
        end
      end

      # A grey, slightly crooked, noisy scan without a text layer.
      def scan_pdf(spec, pdf, target)
        dir = WORK_DIR.join("scan", spec.key).to_s
        FileUtils.rm_rf(dir) && FileUtils.mkdir_p(dir)
        run!("pdftoppm", "-r", "150", "-gray", "-png", pdf, File.join(dir, "page"))
        pages = Dir[File.join(dir, "page-*.png")].sort.map.with_index do |page, index|
          scanned = File.join(dir, format("scan-%02d.png", index))
          run!("convert", page, "-background", "white", "-rotate", (index.even? ? "0.6" : "-0.4"), "-gravity", "center",
            "-extent", "1275x1650", "-attenuate", "0.35", "+noise", "Gaussian", "-blur", "0x0.5", "-level", "6%,97%", scanned)
          scanned
        end
        run!("convert", *pages, "-density", "150", "-units", "PixelsPerInch", "-compress", "jpeg", "-quality", "80", target)
      end

      # A phone photo of a receipt on a table.
      def photo(spec, pdf, target)
        dir = WORK_DIR.join("scan", spec.key).to_s
        FileUtils.rm_rf(dir) && FileUtils.mkdir_p(dir)
        receipt = File.join(dir, "receipt.png")
        tilted = File.join(dir, "tilted.png")
        run!("pdftoppm", "-r", "220", "-png", "-singlefile", pdf, File.join(dir, "receipt"))
        run!("convert", receipt, "-background", "none", "-rotate", "-2.2", "(", "+clone", "-background", "black", "-shadow", "55x14+10+12", ")",
          "+swap", "-background", "none", "-layers", "merge", "+repage", tilted)
        width, height = capture!("identify", "-format", "%w %h", tilted).split.map(&:to_i)
        run!("convert", "-size", "#{width + 260}x#{height + 220}", "xc:#9a8268", "-attenuate", "0.6", "+noise", "Multiplicative", "-blur", "0x1.2",
          tilted, "-gravity", "center", "-composite", "-attenuate", "0.2", "+noise", "Gaussian", "-resize", "1400x1400>", "-quality", "86", target)
      end

      def create_user
        @user = User.create!(name: "Sam Rivera", email_address: EMAIL, password: PASSWORD, admin: true, theme: "system")
        User.create!(name: "Alex Rivera", email_address: "alex@example.com", password: PASSWORD, admin: false)
      end

      def create_settings
        Setting.instance.update!(ai_enabled: false, setup_completed_at: 40.days.ago, ingest_enabled: false)
      end

      def create_taxonomy
        specs.map { it.details[:correspondent] }.uniq.each { Correspondent.create!(name: it) }
        specs.map { it.details[:type] }.uniq.each { DocumentType.create!(name: it) }
        specs.flat_map { it.details[:tags] }.uniq.each { Tag.create!(name: it, color: TAG_COLORS.fetch(it, "slate")) }
        # "Statement" and "Letter" appear in many documents' text, so they are
        # only set by AI or by hand.
        DocumentType.where(name: %w[Statement Letter Receipt Invoice]).update_all(auto_match: false)
        Tag.where(name: %w[home income travel receipts]).update_all(auto_match: false)
      end

      def create_rules
        Rule.create!(name: "Bluefin statements stay private", position: 1, mark_private: true,
          conditions: [ { field: "content", operator: "phrase", value: "Bluefin Credit Union" } ],
          correspondent: Correspondent.find_by!(name: "Bluefin Credit Union"), document_type: DocumentType.find_by!(name: "Bank Statement"),
          tag_ids: Tag.where(name: "bank").ids)
        Rule.create!(name: "Medical records stay private", position: 2, mark_private: true, match_mode: "any",
          conditions: [ { field: "content", operator: "phrase", value: "after-visit summary" }, { field: "filename", operator: "any", value: "medical lab-results" } ],
          document_type: DocumentType.find_by!(name: "Medical Record"), tag_ids: Tag.where(name: "medical").ids)
        Rule.create!(name: "Utility bills", position: 3, match_mode: "any",
          conditions: [ { field: "content", operator: "any", value: "kWh sewer wireless" } ],
          document_type: DocumentType.find_by!(name: "Utility Bill"), tag_ids: Tag.where(name: "utilities").ids)
        Rule.create!(name: "Tax paperwork", position: 4, match_mode: "any",
          conditions: [ { field: "content", operator: "phrase", value: "wage and tax statement" }, { field: "content", operator: "phrase", value: "property tax bill" } ],
          document_type: DocumentType.find_by!(name: "Tax Form"))
        Rule.create!(name: "Scanner receipts", position: 5,
          conditions: [ { field: "source", operator: "is", value: "folder" }, { field: "filename", operator: "regex", value: "^IMG_\\d+" } ],
          document_type: DocumentType.find_by!(name: "Receipt"), tag_ids: Tag.where(name: "receipts").ids)
        Rule.create!(name: "Car paperwork", position: 6, enabled: false,
          conditions: [ { field: "content", operator: "any", value: "VIN odometer" } ], tag_ids: Tag.where(name: "car").ids)
      end

      def ingest_documents
        specs.sort_by { -it.added_days_ago }.to_h do |spec|
          puts "Processing #{spec.filename}"
          document = File.open(WORK_DIR.join("files", spec.filename)) do |io|
            Document.ingest!(io: io, filename: spec.filename, source: spec.source, private: spec.private,
              private_reason: ("Marked private when uploaded" if spec.private), uploaded_by: (@user if spec.source == "upload"),
              source_detail: ("ingest folder" if spec.source == "folder"))
          end
          document.reload
          raise "#{spec.filename} did not process: #{document.error}" unless document.status == "ready"

          [ spec.key, document ]
        end
      end

      def apply_details(documents)
        documents.each do |key, document|
          spec = specs.find { it.key == key }
          details = spec.details
          added = spec.added_days_ago.days.ago.change(hour: 9 + (key.sum % 9), min: key.sum % 60)
          local = details[:local] || document.private?
          document.update_columns(
            title: details[:title], document_date: details[:date],
            correspondent_id: Correspondent.find_by!(name: details[:correspondent]).id,
            document_type_id: DocumentType.find_by!(name: details[:type]).id,
            metadata_source: local ? "rules" : "ai", confidence: (details[:confidence] unless local), ai_model: (AI_MODEL unless local),
            created_at: added, updated_at: added + 2.minutes, processed_at: added + 1.minute,
            steps: finished_steps(document, details, local, added)
          )
          document.summary = details[:summary]
          document.save!(validate: false, touch: false)
          document.tags = Tag.where(name: details[:tags])
          document.refresh_search_vector
          reasons = (document.review_reasons & %w[blank_pages]) + spec.review
          document.update_columns(review_reasons: reasons, needs_review: reasons.any?)
        end
      end

      # The steps a run with AI would have recorded. The search model cannot
      # be downloaded here, so the index step is filled in as it would read.
      def finished_steps(document, details, local, added)
        steps = document.steps.deep_dup
        steps["metadata"] = { "status" => "done", "detail" => local ? "Local rules" : "#{AI_MODEL} · confidence #{(details[:confidence] * 100).round}%" }
        passages = [ (document.content.to_s.length / 900.0).ceil, 1 ].max
        steps["index"] = { "status" => "done", "detail" => "#{passages} #{"passage".pluralize(passages)} embedded locally" }
        steps["duplicates"] = { "status" => "done", "detail" => "None found" }
        steps.transform_values { it.merge("at" => (added + 1.minute).iso8601) }
      end

      def flag_duplicate(documents)
        copy, original = documents.values_at("electric-2026-09-scan", "electric-2026-09")
        steps = copy.steps.merge("duplicates" => copy.steps["duplicates"].merge("detail" => "Looks like “#{original.display_title}”"))
        copy.update_columns(duplicate_of_id: original.id, steps: steps)
        copy.add_review_reason!("possible_duplicate")
      end

      def turn_on_ai
        provider = AIProvider.create!(kind: "openai", name: "OpenAI", api_key: "sk-demo-not-a-real-key")
        Setting.instance.update!(ai_enabled: true, extraction_provider: provider, extraction_model: AI_MODEL,
          research_provider: provider, research_model: "gpt-5.6", vision_provider: provider, vision_model: AI_MODEL)
      end

      def create_conversations(documents)
        id = ->(key) { documents.fetch(key).id }

        conversation(
          "How much did we spend on electricity this summer?", 3.days.ago,
          steps: [ "Searching for “electric bill”", "Searching for “Northwind Utilities summer 2026”",
                   "Reading document ##{id["electric-2026-07"]}", "Reading document ##{id["electric-2026-08"]}", "Reading document ##{id["electric-2026-09"]}" ],
          answer: <<~MARKDOWN,
            Your three summer electric bills from Northwind Utilities add up to **$334.22**:

            | Bill | Usage | Amount |
            | --- | --- | --- |
            | July 2026 | 612 kWh | $98.42 [##{id["electric-2026-07"]}] |
            | August 2026 | 784 kWh | $124.17 [##{id["electric-2026-08"]}] |
            | September 2026 | 701 kWh | $111.63 [##{id["electric-2026-09"]}] |

            $98.42 + $124.17 + $111.63 = **$334.22**

            August was the most expensive month, with usage about 28% above July. Each bill was paid by AutoPay, and summer rates end after September, so the October bill should be lower [##{id["electric-2026-09"]}].
          MARKDOWN
          cited: [ id["electric-2026-07"], id["electric-2026-08"], id["electric-2026-09"] ]
        )

        conversation(
          "What did the hail damage cost us in the end?", 1.day.ago,
          steps: [ "Searching for “hail damage”", "Searching for “claim settlement Harbor Mutual”",
                   "Reading document ##{id["claim"]}", "Reading document ##{id["auto-service"]}", "Searching for “deductible payment”" ],
          answer: <<~MARKDOWN,
            The repair came to **$2,340.00** at Pinecrest Auto Service: dent repair on the hood and roof, a new windshield and a lane camera recalibration [##{id["auto-service"]}].

            Harbor Mutual approved the full estimate and paid **$2,090.00** by direct deposit on May 19, 2026, after the $250 comprehensive deductible [##{id["claim"]}]. So the hail cost you **$250.00** out of pocket, and the claim did not affect your safe-driver discount [##{id["claim"]}].

            The repair has a 12 month / 12,000 mile warranty on parts and labor, until June 2027 [##{id["auto-service"]}].
          MARKDOWN
          cited: [ id["auto-service"], id["claim"] ],
          private_matches: [ id["bank-2026-08"] ]
        )

        conversation(
          "When does the fridge warranty run out?", 6.days.ago,
          steps: [ "Searching for “refrigerator warranty”", "Reading document ##{id["warranty"]}" ],
          answer: <<~MARKDOWN,
            The Atlas Appliance protection plan on the French-door refrigerator runs until **March 7, 2031**, five years from the purchase on March 7, 2026 [##{id["warranty"]}]. It covers parts and labor, including the compressor and ice maker, plus food spoilage up to $250 per claim. To claim, call (555) 010-5600 with certificate AT-000-61450 [##{id["warranty"]}].
          MARKDOWN
          cited: [ id["warranty"] ]
        )
      end

      def conversation(question, at, steps:, answer:, cited:, private_matches: [])
        conversation = @user.conversations.create!(title: question, created_at: at, updated_at: at + 1.minute)
        conversation.messages.create!(role: "user", content: question, created_at: at, updated_at: at)
        conversation.messages.create!(
          role: "assistant", status: "complete", model: "gpt-5.6", content: answer.strip, cited_document_ids: cited, used_document_ids: cited,
          private_match_ids: private_matches, provenance_complete: true, created_at: at + 2.seconds, updated_at: at + 41.seconds,
          steps: steps.each_with_index.map { |label, index| { "label" => label, "at" => (at + (index * 6).seconds).iso8601 } }
        )
      end

      def run!(*command)
        output, status = Open3.capture2e(*command.map(&:to_s))
        raise "#{command.first} failed: #{output}" unless status.success?

        output
      end

      def capture!(*command)
        run!(*command)
      end
  end
end
