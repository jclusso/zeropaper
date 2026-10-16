module DocumentsHelper
  TAG_COLORS = {
    "slate" => "border-border bg-muted/60 text-muted-foreground",
    "red" => "border-red-500/30 bg-red-500/10 text-red-700 dark:text-red-300",
    "orange" => "border-orange-500/30 bg-orange-500/10 text-orange-700 dark:text-orange-300",
    "amber" => "border-amber-500/30 bg-amber-500/10 text-amber-800 dark:text-amber-300",
    "lime" => "border-lime-500/30 bg-lime-500/10 text-lime-800 dark:text-lime-300",
    "emerald" => "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
    "teal" => "border-teal-500/30 bg-teal-500/10 text-teal-700 dark:text-teal-300",
    "sky" => "border-sky-500/30 bg-sky-500/10 text-sky-700 dark:text-sky-300",
    "indigo" => "border-indigo-500/30 bg-indigo-500/10 text-indigo-700 dark:text-indigo-300",
    "violet" => "border-violet-500/30 bg-violet-500/10 text-violet-700 dark:text-violet-300",
    "pink" => "border-pink-500/30 bg-pink-500/10 text-pink-700 dark:text-pink-300"
  }.freeze

  # Solid swatches for picking a tag's color.
  TAG_SWATCHES = {
    "slate" => "bg-neutral-400", "red" => "bg-red-500", "orange" => "bg-orange-500", "amber" => "bg-amber-400",
    "lime" => "bg-lime-500", "emerald" => "bg-emerald-500", "teal" => "bg-teal-500", "sky" => "bg-sky-500",
    "indigo" => "bg-indigo-500", "violet" => "bg-violet-500", "pink" => "bg-pink-500"
  }.freeze

  STEP_STYLES = {
    "done" => [ :check, "border-success/40 bg-success/10 text-success" ],
    "running" => [ :refresh, "border-strong-accent/40 bg-strong-accent/10 text-strong-accent animate-pulse" ],
    "failed" => [ :x, "border-danger/40 bg-danger/10 text-danger" ],
    "skipped" => [ :minus, "border-border bg-muted text-muted-foreground" ]
  }.freeze

  def tag_chip(document_tag, link: true)
    classes = tag_chip_class(document_tag)
    link ? link_to(document_tag.name, documents_path(tag_ids: [ document_tag.id ]), class: classes) : tag.span(document_tag.name, class: classes)
  end

  # Chip classes for a tag, or for a new tag not saved yet.
  def tag_chip_class(document_tag)
    "inline-flex items-center rounded-xs border px-1.5 py-px text-[0.7rem] font-medium #{TAG_COLORS.fetch(document_tag&.color, TAG_COLORS["slate"])}"
  end

  def privacy_badge(document)
    return unless document.private?

    private_badge(reason: document.private_reason, interactive: false)
  end

  def status_badge(document)
    case document.status
    when "pending" then tag.span("Queued", class: "badge-slate")
    when "processing" then tag.span(class: "badge-accent") { tag.span(class: "size-1.5 bg-current animate-pulse") + "Processing" }
    when "failed"
      badge = tag.span("Failed", class: "badge-red #{"cursor-help" if document.error.present?}")
      document.error.present? ? render(layout: "shared/tooltip", locals: { text: document.error, tone: "danger" }) { badge } : badge
    end
  end

  ReviewItem = Struct.new(:key, :icon, :tone, :message, :actions, keyword_init: true)

  # Everything on a document that wants attention, as one list for the review
  # bar: review reasons with their fixes, plus notes such as turned pages.
  def review_items(document)
    return [] if document.processing?

    items = []
    if document.status == "failed"
      items << ReviewItem.new(key: "failed", icon: :warning, tone: "text-danger", message: "Processing failed: #{document.error}",
        actions: button_to("Retry", document_reprocessing_path(document), class: "btn-secondary btn-sm"))
    end

    if (pages = document.suggested_blank_pages).any?
      items << ReviewItem.new(key: "blank_pages", icon: :grid, tone: "text-warning",
        message: "#{pluralize(pages.size, "page")} #{pages.size == 1 ? "looks" : "look"} blank (#{pages.to_sentence}).",
        actions: safe_join([ tag.button("Review pages", type: "button", class: "btn-secondary btn-sm", command: "show-modal", commandfor: "pages-dialog"),
          button_to("Not blank", document_page_removal_path(document), params: { version: document.checksum }, class: "btn-ghost btn-sm", title: "Keep these pages and read them") ]))
    end

    if document.duplicate_of
      items << ReviewItem.new(key: "possible_duplicate", icon: :copy, tone: "text-warning",
        message: "Looks like a duplicate of “#{document.duplicate_of.display_title}”.",
        actions: safe_join([ link_to("Compare", document_comparison_path(document), class: "btn-secondary btn-sm"),
          button_to("Not a duplicate", document_duplicate_dismissal_path(document), class: "btn-ghost btn-sm") ]))
    end

    detail_reasons = document.review_reasons & %w[low_confidence missing_details ai_failed]
    if detail_reasons.any?
      items << ReviewItem.new(key: "details", icon: :pencil, tone: "text-warning",
        message: "#{detail_reasons.map { |reason| Document::Reviewable::REASONS[reason] }.to_sentence}. Check the details.",
        actions: safe_join([ tag.button("Edit details", type: "button", class: "btn-secondary btn-sm",
          data: { action: "tabs#select toggle#show", tabs_name_param: "details" }),
          button_to("Details are right", document_review_path(document), class: "btn-ghost btn-sm") ]))
    end

    if document.needs_review? && items.none?
      message = document.review_reasons.include?("always") ? "New document. Check that it looks right." : "#{document.review_reason_labels.to_sentence}."
      items << ReviewItem.new(key: "always", icon: :inbox, tone: "muted", message: message,
        actions: button_to(document_review_path(document), class: "btn-secondary btn-sm") { safe_join([ icon(:check, class: "size-3.5"), " Looks good" ]) })
    end

    if (pages = rotated_pages(document)).any?
      restore = button_to("Restore original", document_original_restoration_path(document), params: { version: document.checksum }, class: "btn-danger btn-sm",
        form: { data: { turbo_confirm: "Restore the file as it was uploaded? This also undoes any page removals, and the document is read again." } })
      items << ReviewItem.new(key: "rotated", icon: :rotate, tone: "text-strong-accent",
        message: "#{pages.size == 1 ? "Page" : "Pages"} #{pages.to_sentence} #{pages.size == 1 ? "was" : "were"} turned upright.",
        actions: (restore if document.original_file.attached?))
    end

    items
  end

  def rotated_pages(document)
    rotated = document.page_record["rotated"].to_h.select { |_page, degrees| degrees.to_i % 360 != 0 }
    rotated.keys.filter_map { |page| document.current_page_number(page.to_i) }.sort
  end

  # "Reading text… step 4 of 7" while processing, or nil.
  def processing_summary(document)
    progress = processing_progress(document)
    return unless progress
    return progress[:label] unless progress[:step]

    "#{progress[:label]}… step #{progress[:step]} of #{progress[:steps]}"
  end

  # Where processing is: the current step's label, its number, and how far
  # along the pipeline is from 0 to 1. Nil when not processing.
  def processing_progress(document)
    return unless document.processing?

    steps = Document::Processing::STEPS.to_a
    return { label: "Waiting for a worker", fraction: 0 } if document.status == "pending" || document.steps.blank?

    index = steps.index { |name, _| document.step_state(name)["status"] == "running" }
    index ||= steps.rindex { |name, _| document.step_state(name)["status"].present? }.to_i
    { label: steps[index].last, step: index + 1, steps: steps.size, fraction: index.fdiv(steps.size) }
  end

  # Which providers a non-private document may be sent to, one line per task.
  def document_exposure(document)
    settings = document.settings
    {
      "OCR" => (Outbound.model_label(:vision) if settings.task_configured?(:vision)),
      "Details" => (Outbound.model_label(:extraction) if settings.task_configured?(:extraction)),
      "Research" => (Outbound.model_label(:research) if settings.task_configured?(:research))
    }.compact
  end

  def document_kind_icon(document)
    if document.pdf? then :document
    elsif document.image? then :photo
    elsif document.spreadsheet? then :table
    else :document
    end
  end

  def step_marker(status)
    name, classes = STEP_STYLES.fetch(status.to_s) { [ :minus, "border-border text-muted-foreground/50" ] }
    tag.span(icon(name, class: "size-3", "stroke-width": "2.5"), class: "flex size-5 shrink-0 items-center justify-center rounded-xs border #{classes}")
  end

  # One page of extracted text.
  def page_text(document, text)
    if document.markdown_text?
      tag.div(render_markdown(text, hardbreaks: true), class: "prose-answer wrap-anywhere")
    else
      tag.div(text, class: "whitespace-pre-wrap wrap-anywhere font-mono text-[13px] leading-6")
    end
  end

  def document_viewer_kind(document)
    if document.viewable_pdf&.attached? then :pdf
    elsif document.image? then :image
    elsif document.spreadsheet? then :spreadsheet
    else :text
    end
  end

  def month_heading(date)
    date.year == Date.current.year ? date.strftime("%B") : date.strftime("%B %Y")
  end

  def filter_query(filters, **changes)
    filters.merge(changes.stringify_keys).compact_blank
  end
end
