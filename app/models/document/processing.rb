# The pipeline a document runs through after ingest. Each step records its
# progress in `steps` so the UI can show where a document is and what ran.
#
# Order matters for privacy: everything that can make a document private
# (filename and source rules, then content rules on locally read text) runs
# before the first step that may send it to a hosted provider.
#
# A run stops at its next step, save or attachment once it is no longer
# current: when a newer run replaced it, or when the document's privacy
# changed underneath it. Outbound also re-reads privacy before each request.
module Document::Processing
  extend ActiveSupport::Concern

  included do
    before_save :ensure_current_run
    # A deleted document discards its queued run; a running one finds its
    # row gone at the next save and stops without attaching anything.
    before_destroy :discard_queued_processing
  end

  STEPS = {
    "inspect" => "Inspect file",
    "orientation" => "Fix page orientation",
    "blank_pages" => "Find blank pages",
    "text" => "Read text",
    "metadata" => "Extract details",
    "index" => "Index for search",
    "duplicates" => "Check for duplicates"
  }.freeze

  PAGE_BREAK = "\f".freeze
  # A document processing longer than this with no live job behind it is
  # stuck, usually because its worker was killed by a restart.
  STUCK_AFTER = 15.minutes
  STUCK_MESSAGE = "Processing stopped unexpectedly, probably because the app restarted. Retry to process it again.".freeze

  # Raised inside a run that was stopped or replaced by a newer one.
  class Stopped < StandardError; end

  class_methods do
    def recover_stuck
      where(status: %w[pending processing]).where(updated_at: ...STUCK_AFTER.ago).find_each do |document|
        document.stop_processing!(STUCK_MESSAGE) unless document.processing_job_alive?
      end
    end
  end

  # Queues a run. Any run already going sees it is no longer current and
  # stops at its next step, which is how Restart works.
  def process_later(extract_metadata: true)
    if persisted?
      update_columns(status: "pending", processing_run: nil, updated_at: Time.current)
      needs_review? ? broadcast_review_changes : broadcast_changes
    end
    ProcessDocumentJob.perform_later(self, extract_metadata: extract_metadata)
  end

  def stop_processing!(reason = "Stopped before it finished.")
    return unless processing?

    update_columns(status: "failed", processing_run: nil, error: reason, updated_at: Time.current)
    add_review_reason!("failed")
    discard_queued_processing
    broadcast_review_changes
  end

  # Whether a queued or running job will still pick this document up.
  def processing_job_alive?
    processing_jobs.any? { |job| !job.finished? && job.failed_execution.nil? }
  end

  def process!(extract_metadata: true)
    @run = nil
    run = SecureRandom.hex(8)
    update!(status: "processing", error: nil, steps: {}, processing_run: run)
    @run = run
    screen_before_content

    with_file_copy do |path|
      run_step("inspect") { inspect_file(path) }
      run_step("orientation") { fix_orientation(path) }
      run_step("blank_pages") { find_blank_pages(path) }
      run_step("text") { read_text(path) }
      run_step("metadata") { extract_metadata ? extract_metadata! : :skipped }
    end
    run_step("index") { index_or_wait! }
    run_step("duplicates") do
      record_page_hashes!
      flag_possible_duplicate
    end

    apply_for_current_run do
      flag_for_review_after_processing
      update!(status: "ready", processed_at: Time.current, processing_run: nil)
    end
  rescue Stopped
    Rails.logger.info("[process] document #{id}: run #{@run} stopped")
  rescue StandardError => error
    # The message can quote the document, so the log gets the class and
    # backtrace only; the message is kept on the document for the person.
    Rails.logger.error("[process] document #{id}: #{error.class}\n#{error.backtrace&.first(10)&.join("\n")}")
    return unless current_run?

    update_columns(status: "failed", error: error.message.truncate(1_000), processing_run: nil, updated_at: Time.current)
    add_review_reason!("failed")
    broadcast_review_changes
  ensure
    @run = nil
  end

  def processing?
    status.in?(%w[pending processing])
  end

  # Applies what a run received, such as an AI answer, in one transaction
  # that holds the row lock, and only while the run is still current.
  # Raises Stopped before writing anything otherwise.
  def apply_for_current_run
    transaction do
      raise Stopped unless current_run?(lock: true)

      yield
    end
  end

  def step_state(name)
    steps.fetch(name, {})
  end

  # Text split back into pages; blank pages that were not read are empty.
  def page_texts
    content.to_s.split(PAGE_BREAK, -1)
  end

  # AI and Docling write page text as Markdown; Tesseract and embedded text
  # are plain lines.
  def markdown_text?
    engine = text_source.to_s.split(" + ").first
    engine.present? && %w[native tesseract].exclude?(engine)
  end

  # Where the text came from, for people: "Embedded text", "Tesseract (local)",
  # "OpenAI · gpt-5.6-luna + embedded text".
  def text_source_label
    return if text_source.blank?
    return "Embedded text" if text_source == "native"

    engine, embedded = text_source.split(" + ", 2)
    [ Setting::LOCAL_OCR_PROVIDERS.fetch(engine, engine), embedded ].compact.join(" + ")
  end

  def with_file_copy
    file.open { |tempfile| yield tempfile.path }
  end

  def generate_thumbnail(path, pdf: pdf?)
    image =
      if pdf
        Pdf.render_page(path, 1, edge: 640, format: :jpeg)
      elsif image?
        ImageProcessing::Vips.source(path).resize_to_limit(640, 640).convert("jpeg").call.read
      end
    return unless image

    thumbnail.attach(io: StringIO.new(image), filename: "thumbnail.jpg", content_type: "image/jpeg")
  end

  private
    def run_step(name)
      raise Stopped unless current_run?

      record_step(name, "running")
      detail = timed("#{name} step") { yield }
      case detail
      when :skipped then record_step(name, "skipped")
      when :waiting then record_step(name, "waiting", Document::INDEX_WAITING_NOTE)
      else record_step(name, "done", detail.is_a?(String) ? detail : nil)
      end
    rescue Stopped
      raise
    rescue StandardError => error
      record_step(name, "failed", error.message.truncate(300))
      raise
    end

    # Whether this run may go on: no newer run replaced it, and the stored
    # privacy is still what this run last read or wrote. Read past the query
    # cache, which jobs run with.
    def current_run?(lock: false)
      return true if @run.nil?

      scope = self.class.where(id: id)
      stored_run, stored_private = self.class.uncached { (lock ? scope.lock : scope).pick(:processing_run, :private) }
      stored_run == @run && stored_private == private_in_database
    end

    # Every save a run makes, including attaching files, waits here for the
    # row lock, so a stale run cannot write AI results after the document
    # went private.
    def ensure_current_run
      raise Stopped unless current_run?(lock: true)
    end

    def processing_jobs
      return [] unless defined?(SolidQueue::Job) && SolidQueue::Job.table_exists?

      SolidQueue::Job.where(concurrency_key: ProcessDocumentJob.new(self).concurrency_key, finished_at: nil)
    end

    def discard_queued_processing
      processing_jobs.each do |job|
        job.discard unless job.finished? || job.claimed_execution
      rescue SolidQueue::Execution::UndiscardableError
        next
      end
    end

    # A stopped run leaves the steps to the run that replaced it.
    def record_step(name, status, detail = nil)
      steps[name] = { "status" => status, "detail" => detail, "at" => Time.current.iso8601 }.compact
      apply_for_current_run { update_columns(steps: steps, updated_at: Time.current) }
      broadcast_changes
    end

    def inspect_file(path)
      self.page_count = pdf? ? Pdf.page_count(path) : 1
      generate_thumbnail(path)
      save!
      pdf? ? "#{page_count} #{"page".pluralize(page_count)}" : content_type
    end

    # Turns pages scanned upside down or sideways, before anything reads
    # them. The stored file is corrected so the viewer shows it upright, the
    # upload is kept in original_file, and the working copy at path is
    # replaced so later steps see upright pages. Runs locally for every
    # document, private or not.
    def fix_orientation(path)
      return :skipped unless (pdf? || image?) && settings.auto_rotate_pages?

      rotations = pdf? ? Orientation.pdf_rotations(path, page_count.to_i) : { 1 => Orientation.image_rotation(path) }.compact
      return "All pages upright" if rotations.empty?

      Dir.mktmpdir do |dir|
        output = File.join(dir, "upright#{File.extname(path)}")
        if pdf?
          Pdf.rotate_pages(path, rotations, output)
        else
          ImageProcessing::Vips.source(path).rotate(rotations[1]).call(destination: output)
        end

        data = File.binread(output)
        checksum = Digest::SHA256.hexdigest(data)
        original_file.attach(io: File.open(path), filename: file.filename, content_type: file.content_type) unless original_file.attached?
        file.attach(io: StringIO.new(data), filename: file.filename, content_type: file.content_type)
        FileUtils.cp(output, path)
        generate_thumbnail(path)
        update!(checksum: checksum, page_record: page_record.merge("rotated" => recorded_rotations(rotations)))
      end

      "Turned #{"page".pluralize(rotations.size)} #{rotations.keys.sort.to_sentence}"
    end

    # Rotations so far, by original page number, as clockwise degrees.
    def recorded_rotations(rotations)
      rotations.each_with_object(page_record.fetch("rotated", {}).dup) do |(page, degrees), recorded|
        key = original_page_number(page).to_s
        total = (recorded.fetch(key, 0) + degrees) % 360
        total.zero? ? recorded.delete(key) : recorded[key] = total
      end
    end

    def find_blank_pages(path)
      return :skipped unless pdf? && page_count.to_i > 1 && settings.blank_page_detection?

      verdicts = BlankPages::Detector.new(path, page_count).call
      detail = nil
      if verdicts.any? { |verdict| !verdict.sure } && BlankPages::Judge.available_for?(self)
        begin
          raise Stopped unless current_run?

          verdicts = BlankPages::Judge.new(self).call(path, verdicts)
          detail = "unclear pages checked with #{Outbound.model_label(:vision)}"
        rescue Stopped, Outbound::PrivateDocumentError
          raise
        rescue StandardError => error
          detail = "AI check failed, kept local verdicts (#{error.message.truncate(80)})"
        end
      elsif verdicts.any? { |verdict| !verdict.sure } && BlankPages::Judge.offered_for?(self)
        detail = "AI check skipped because privacy rules read the text first"
      end
      record_blank_pages(verdicts)
      add_review_reason!("blank_pages") if suggested_blank_pages.any?

      [ "#{suggested_blank_pages.size} blank #{"page".pluralize(suggested_blank_pages.size)} found", detail ].compact.join(", ")
    end

    # Embedded text is used where it can be trusted; everything else is read
    # by OCR: scans, pages with a scanner's own OCR layer, and pages whose
    # text layer extracts as garbage. Privacy rules see every page, blank
    # ones included, even though blank pages are left out of the text.
    def read_text(path)
      @text_note = nil
      @ocr_runs = {}
      read_pages = []
      @screening_pages = [ [], :skip ]
      @skipped_pages = [ [], :skip ]
      if pdf?
        native = NativeText.pdf_pages(path)
        trusted = native.select(&:trusted?).to_h { |page| [ page.number, page.text ] }
        untrusted = (1..page_count.to_i).to_a - trusted.keys
        @screening_pages = [ untrusted, ocr_mode(native, untrusted) ]
        read_pages = pages_to_read - trusted.keys
        @skipped_pages = [ untrusted - read_pages, ocr_mode(native, untrusted - read_pages) ]
        record_ocr_skipped((1..page_count.to_i).to_a - pages_to_read)

        if read_pages.empty?
          self.text_source = "native"
          texts = (1..page_count.to_i).map { |page| trusted[page].to_s }
        else
          mode = ocr_mode(native, read_pages)
          read = read_scanned_text(path, read_pages, mode: mode, embedded: trusted.values)
          texts = (1..page_count.to_i).map { |page| trusted[page] || read[page].to_s }
          self.text_source = "#{text_source} + embedded text" if trusted.any?
        end
      elsif (texts = NativeText.extract(path, content_type))
        self.text_source = "native"
        record_ocr_skipped([])
      else
        record_ocr_skipped([])
        read_pages = [ 1 ]
        @screening_pages = [ read_pages, :skip ]
        read = read_scanned_text(path, read_pages)
        texts = [ read[1].to_s ]
      end

      self.content = texts.map(&:strip).join(PAGE_BREAK)
      save!
      screen_for_privacy([ content, *skipped_page_texts(path) ].join("\n"))
      [ "#{text_source_label} · #{content.to_s.squish.length} characters", @text_note ].compact.join(". ")
    ensure
      @ocr_runs&.each_value { |run| FileUtils.rm_rf(File.dirname(run.archive_path)) if run&.archive_path }
    end

    def ocr_mode(native, pages)
      chosen = native.select { |page| page.number.in?(pages) }
      if chosen.any? { |page| !page.scanned && page.text.squish.present? }
        :force
      elsif native.any? { |page| page.text.squish.present? }
        :redo
      else
        :skip
      end
    end

    # OCR for the given pages. Tesseract makes the searchable PDF the viewer
    # shows. When AI reads scans and local rules could still make the
    # document private, the whole document is screened locally before
    # anything leaves: the embedded text of the other pages together with
    # local OCR of these. If the AI model fails, the local engine reads the
    # pages instead. Returns { page => text }.
    def read_scanned_text(path, pages, mode: :skip, embedded: [])
      ai_reads = settings.ai_reads_scans_for?(self)
      # With nothing to check locally first, Tesseract builds the searchable
      # PDF while the AI model reads the pages.
      searchable = start_searchable_pdf(path, pages, mode, alongside: ai_reads && !needs_privacy_screening?)

      texts = read_with_ai(path, pages, mode, embedded) if ai_reads
      texts ||= begin
        engine = settings.local_ocr_engine
        self.text_source = engine
        engine_run = engine == "tesseract" && searchable ? searchable.value : local_ocr(engine, path, pages, mode)
        engine_run.pages
      end

      attach_searchable_pdf(finished_searchable_pdf(searchable))
      texts
    ensure
      finished_searchable_pdf(searchable)
    end

    # The searchable-PDF run, in the background when it can overlap with the
    # AI read, otherwise finished before returning.
    def start_searchable_pdf(path, pages, mode, alongside:)
      return unless settings.searchable_pdf?

      run = Thread.new { local_ocr("tesseract", path, pages, mode) }
      run.report_on_exception = false
      run.join unless alongside
      run
    end

    # The searchable PDF is an extra: when only it fails, the document keeps
    # the text that was read and the viewer shows the file as uploaded. When
    # Tesseract was also the reader, its failure already surfaced above.
    def finished_searchable_pdf(run)
      run&.value
    rescue StandardError => error
      @searchable_error ||= error.message.squish.truncate(160).tap do |message|
        @text_note = [ @text_note, "No searchable PDF (#{message})" ].compact.join(". ")
      end
      nil
    end

    def attach_searchable_pdf(run)
      return unless run&.archive_path

      archive_file.attach(io: File.open(run.archive_path), filename: "#{File.basename(original_filename, ".*")}.pdf", content_type: "application/pdf")
      # The viewer shows the searchable PDF, whose pages may be straightened.
      generate_thumbnail(run.archive_path, pdf: true)
    end

    # Returns the AI model's page texts, or nil when it could not read them.
    def read_with_ai(path, pages, mode, embedded = [])
      screen_for_privacy([ *embedded, screening_ocr(path).text ].join("\n")) if needs_privacy_screening?
      return unless settings.ai_reads_scans_for?(self)
      raise Stopped unless current_run?

      result = timed("AI read of #{pages.size} #{"page".pluralize(pages.size)}") { Ocr::AI.new(settings, self).call(path, pages: pages, content_type: content_type) }
      self.text_source = Outbound.model_label(:vision)
      result.pages
    rescue Stopped, Outbound::PrivateDocumentError
      raise
    rescue StandardError => error
      @text_note = "AI could not read it (#{error.message.truncate(80)}), used #{settings.local_ocr_label}"
      nil
    end

    # Local OCR of every page without trusted text, blank ones included, for
    # the privacy rules: a page judged blank may still hold text.
    def screening_ocr(path)
      pages, mode = @screening_pages
      local_ocr(settings.local_ocr_engine, path, pages, mode)
    end

    # What the pages left out as blank say, read locally, while content
    # rules still need to see them. Taken from the screening run when one
    # read every page already; otherwise only these pages are read.
    def skipped_page_texts(path)
      skipped, mode = @skipped_pages
      return [] if skipped.empty? || !needs_privacy_screening?

      engine = settings.local_ocr_engine
      run = @ocr_runs[[ engine, *@screening_pages ]] || local_ocr(engine, path, skipped, mode)
      run.pages.values_at(*skipped).map(&:to_s)
    end

    # Runs a local engine once per set of pages in a document pass and
    # reuses its result.
    def local_ocr(engine, path, pages, mode)
      key = [ engine, pages, mode ]
      return @ocr_runs[key] if @ocr_runs.key?(key)

      @ocr_runs[key] = timed("#{engine} read of #{pages.size} #{"page".pluralize(pages.size)}") do
        if engine == "tesseract"
          Ocr::Tesseract.new(settings).call(path, pages: pages, content_type: content_type, mode: mode)
        else
          Ocr.engine(engine, settings).call(path, pages: pages, content_type: content_type)
        end
      end
    end

    # Logs how long the block ran, whether it finished or raised, so a slow
    # document shows which part was slow. Reads and AI requests run at the
    # same time in a step, so each logs on its own.
    def timed(label)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      Rails.logger.info("[process] document #{id}: #{label} took #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)}s") if started
    end

    def extract_metadata!
      if private? || !settings.ai_configured?
        Metadata::Rules.new(self).apply
        "Local rules"
      else
        begin
          raise Stopped unless current_run?

          Metadata::AI.new(self).apply
          "#{ai_model} · confidence #{(confidence.to_f * 100).round}%"
        rescue Outbound::PrivateDocumentError => error
          raise Stopped unless current_run?
          raise if error.document_ids.include?(id)

          # Another document the request carried, such as an example title,
          # turned private. This one is still fine to file without the AI.
          Metadata::Rules.new(self).apply
          add_review_reason!("ai_failed")
          "AI failed (a document it was shown became private), used local rules"
        rescue Outbound::Error, RubyLLM::Error, Faraday::Error => error
          Metadata::Rules.new(self).apply
          add_review_reason!("ai_failed")
          "AI failed (#{error.message.truncate(80)}), used local rules"
        end
      end
    end
end
