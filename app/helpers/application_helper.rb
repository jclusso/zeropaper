module ApplicationHelper
  THEMES = { "system" => "Match the system", "light" => "Light", "dark" => "Dark" }.freeze
  NO_AUTOFILL = { autocomplete: "off", data: { "1p-ignore": true, lpignore: "true", bwignore: true, form_type: "other" } }.freeze

  # Field options for anything that is not about a person, such as rule, tag
  # and document names, so browsers and password managers do not offer
  # contacts and addresses.
  def no_autofill(options = {})
    options.merge(autocomplete: "off", data: (options[:data] || {}).merge(NO_AUTOFILL[:data]))
  end

  def theme_preference
    Current.user&.theme.presence_in(THEMES.keys) || "system"
  end

  def nav_link_to(name, path, icon:, active: current_page?(path), count: nil)
    link_to path, class: [ "nav-link", ("nav-link-active" if active) ], "aria-current": (active ? "page" : nil) do
      safe_join([
        icon(icon, class: "size-4.5 shrink-0"),
        tag.span(name, class: "flex-1"),
        (tag.span(count, class: "rounded-xs bg-strong-accent px-1.5 py-px text-[0.7rem] font-bold text-strong-accent-foreground tabular-nums") if count.to_i.positive?)
      ].compact)
    end
  end

  def page_header(title, subtitle = nil, &actions)
    tag.div(class: "mb-6 flex flex-wrap items-end justify-between gap-4") do
      tag.div { safe_join([ tag.h1(title, class: "page-title"), (tag.p(subtitle, class: "mt-1 max-w-2xl text-sm muted") if subtitle) ].compact) } +
        (actions ? tag.div(class: "flex flex-wrap items-center gap-2", &actions) : "".html_safe)
    end
  end

  def form_errors(record)
    return if record.errors.empty?

    tag.div(class: "callout-danger mb-5", role: "alert") do
      icon(:warning, class: "mt-0.5 size-4 shrink-0 text-danger") +
        tag.ul(class: "flex-1 space-y-1") { safe_join(record.errors.full_messages.map { |message| tag.li(message) }) }
    end
  end

  # A labelled value in Zerobyte's stat style: small uppercase label, value below.
  def stat(label, value)
    tag.div { tag.p(label, class: "eyebrow") + tag.p(value.presence || "None", class: "mt-1 text-sm font-medium break-words") }
  end
end
