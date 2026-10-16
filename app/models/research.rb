# Research: a tool-calling agent that searches, reads, counts and
# totals across the library, streams its progress into the answer message,
# and cites the documents behind each claim.
#
# Privacy: the search tools run locally over every document, but only
# non-private documents are ever handed to the model (Outbound#release!).
# Private matches are collected separately and shown to the person, never to
# the model. Every document handed to the model is checked again before each
# request of the run, and recorded on the answer so a later question leaves
# that turn out of its history once the document is private.
class Research
  MAX_HISTORY = 20

  attr_reader :message, :cited_ids, :private_match_ids

  def initialize(message)
    @message = message
    @cited_ids = Set.new
    @private_match_ids = Set.new
    @outbound = Outbound.without_documents
  end

  def run
    chat = @outbound
      .chat(:research)
      .with_instructions(instructions)
      .with_tools(*tools)
    load_history(chat)
    chat.before_tool_call { |tool_call| message.add_step!(step_label(tool_call)) }

    response = chat.ask(question) { |chunk| message.append!(chunk.content) }

    content = response.content.to_s
    message.finish!(
      content: content,
      cited_document_ids: (content.scan(/\[#(\d+)\]/).flatten.map(&:to_i) & cited_ids.to_a),
      used_document_ids: cited_ids.to_a,
      private_match_ids: private_match_ids.to_a
    )
  rescue StandardError => error
    Rails.logger.error("[research] message #{message.id}: #{error.class}: #{error.message}")
    message.fail!(error.is_a?(Outbound::Error) ? error.message : "#{error.class.name.demodulize}: #{error.message.truncate(200)}")
  end

  # Called by tools with the documents a search matched. Shareable ones may
  # go to the model and be cited; private ones are only remembered.
  def shareable(documents)
    private_docs, shared = documents.partition(&:private?)
    private_match_ids.merge(private_docs.map(&:id))
    released = @outbound.release!(shared)
    cited_ids.merge(shared.map(&:id))
    released
  end

  private
    def conversation
      message.conversation
    end

    def question_message
      @question_message ||= conversation.messages.where(role: "user").where("id < ?", message.id).last
    end

    def question
      question_message.content
    end

    # Earlier turns, without those that used a document that is private now.
    # Their documents are checked before each request too.
    def load_history(chat)
      history = conversation.shareable_history(before: question_message, limit: MAX_HISTORY)
      @outbound.release!(Document.where(id: history.flat_map(&:shared_document_ids)).to_a)
      history.each { |earlier| chat.add_message(role: earlier.role.to_sym, content: earlier.content) }
    end

    def tools
      [ Research::SearchDocuments, Research::ReadDocument, Research::CountDocuments, Research::ListTaxonomy ].map { |tool| tool.new(self) }
    end

    def step_label(tool_call)
      arguments = tool_call.arguments.to_h.with_indifferent_access
      case tool_call.name
      when /search_documents/ then "Searching for “#{arguments[:query]}”"
      when /read_document/ then reading_label(arguments[:id])
      when /count_documents/ then "Counting documents by #{arguments[:group_by].to_s.humanize(capitalize: false)}"
      when /list_taxonomy/ then "Listing correspondents, types and tags"
      else "Running #{tool_call.name}"
      end
    end

    # Names the document being read. Private documents are never read, so
    # their titles are never shown either.
    def reading_label(id)
      title = Document.shareable.find_by(id: id)&.display_title
      title ? "Reading “#{title.truncate(60)}”" : "Reading document ##{id}"
    end

    def instructions
      <<~TEXT
        You are a research assistant for a personal document archive. Answer the question using the tools:
        search the archive (try several phrasings and filters), read the documents that matter, and use
        count_documents for questions about how many. When asked for totals, read each relevant document,
        list the amounts you used, then add them up and show the sum.

        Cite every claim with the document id in this exact form: [#123]. Only cite documents you received
        from a tool. If the archive does not contain the answer, say so plainly. Some documents are private
        and are not available to you; never guess at their contents.

        Use Markdown. Keep answers direct. Today is #{Date.current.iso8601}.
      TEXT
    end
end
