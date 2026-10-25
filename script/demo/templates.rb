# HTML for the demo documents. Every name, address and number here is made
# up: addresses use Sample Street and ZIP 00000, phone numbers are 555-01xx
# and email addresses are on example.com.
module Demo
  module Templates
    HOUSEHOLD = [ "Sam & Alex Rivera", "42 Sample Street", "Brightwater, ST 00000" ].freeze

    BASE_CSS = <<~CSS.freeze
      @page { margin: 0; }
      * { box-sizing: border-box; }
      html, body { margin: 0; padding: 0; }
      body { font-family: "Helvetica Neue", Arial, "Liberation Sans", sans-serif; color: #1f2328; font-size: 10.5pt; line-height: 1.45; }
      .page { width: 8.5in; height: 11in; padding: 0.7in 0.75in; position: relative; overflow: hidden; page-break-after: always; }
      .page:last-child { page-break-after: auto; }
      .head { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 3px solid var(--accent); padding-bottom: 14px; margin-bottom: 22px; }
      .brand { display: flex; align-items: center; gap: 12px; }
      .logo { width: 44px; height: 44px; border-radius: 10px; background: var(--accent); color: #fff; font-weight: 700; font-size: 17pt; display: flex; align-items: center; justify-content: center; }
      .brand h1 { margin: 0; font-size: 16pt; letter-spacing: -0.01em; }
      .brand p, .from p { margin: 0; color: #57606a; font-size: 8.5pt; }
      .from { text-align: right; }
      .meta { display: flex; justify-content: space-between; margin-bottom: 22px; }
      .meta .to p { margin: 0; }
      .meta table td { padding: 1px 0 1px 18px; }
      .meta table td:first-child { color: #57606a; padding-left: 0; }
      h2 { font-size: 13pt; margin: 0 0 10px; color: var(--accent); }
      h3 { font-size: 10.5pt; margin: 18px 0 6px; text-transform: uppercase; letter-spacing: 0.06em; color: #57606a; }
      table.lines { width: 100%; border-collapse: collapse; margin: 8px 0 14px; }
      table.lines th { text-align: left; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.05em; color: #57606a; border-bottom: 1px solid #d0d7de; padding: 6px 4px; }
      table.lines td { border-bottom: 1px solid #eaeef2; padding: 6px 4px; vertical-align: top; }
      table.lines .num { text-align: right; white-space: nowrap; }
      table.lines tr.total td { font-weight: 700; border-bottom: none; border-top: 2px solid #1f2328; }
      .box { border: 1px solid #d0d7de; border-radius: 6px; padding: 12px 14px; margin: 12px 0; background: #f6f8fa; }
      .due { display: flex; gap: 14px; margin: 14px 0; }
      .due div { flex: 1; border: 1px solid #d0d7de; border-radius: 6px; padding: 10px 12px; }
      .due span { display: block; font-size: 8.5pt; color: #57606a; text-transform: uppercase; letter-spacing: 0.05em; }
      .due strong { font-size: 14pt; }
      .chart { display: flex; align-items: flex-end; gap: 6px; height: 90px; margin: 8px 0 4px; }
      .chart i { flex: 1; background: var(--accent); opacity: 0.75; display: block; }
      .chart i.now { opacity: 1; }
      .months { display: flex; gap: 6px; font-size: 7.5pt; color: #57606a; }
      .months span { flex: 1; text-align: center; }
      .foot { position: absolute; left: 0.75in; right: 0.75in; bottom: 0.5in; font-size: 7.5pt; color: #8c959f; border-top: 1px solid #eaeef2; padding-top: 8px; }
      .stub { position: absolute; left: 0.75in; right: 0.75in; bottom: 0.95in; border-top: 2px dashed #8c959f; padding-top: 12px; display: flex; justify-content: space-between; font-size: 9pt; }
      .sig { margin-top: 28px; }
      .sig .name { font-family: "Brush Script MT", "URW Chancery L", cursive; font-size: 20pt; color: #24356b; }
      p { margin: 0 0 9px; }
      .small { font-size: 8.5pt; color: #57606a; }
      .stamp { display: inline-block; border: 2px solid var(--accent); color: var(--accent); padding: 3px 10px; font-weight: 700; letter-spacing: 0.1em; transform: rotate(-4deg); }
    CSS

    RECEIPT_CSS = <<~CSS.freeze
      @page { margin: 0; }
      html, body { margin: 0; padding: 0; background: #fff; }
      body { font-family: "DejaVu Sans Mono", "Courier New", monospace; font-size: 10pt; color: #222; }
      .receipt { width: 3.4in; padding: 0.3in 0.25in; }
      .c { text-align: center; }
      h1 { font-size: 15pt; margin: 0 0 2px; letter-spacing: 0.05em; }
      p { margin: 0; }
      hr { border: none; border-top: 1px dashed #555; margin: 8px 0; }
      table { width: 100%; border-collapse: collapse; }
      td { padding: 1px 0; vertical-align: top; }
      td.r { text-align: right; white-space: nowrap; }
      .big td { font-size: 12pt; font-weight: 700; }
    CSS

    module_function

    def page_html(body, accent: "#0f766e", width: "8.5in", height: "11in", css: BASE_CSS)
      <<~HTML
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="page-size" content="#{width} #{height}">
        <style>:root { --accent: #{accent}; } #{css}</style></head>
        <body>#{body}</body></html>
      HTML
    end

    def money(amount)
      ActiveSupport::NumberHelper.number_to_currency(amount)
    end

    def header(name:, initials:, tagline:, contact:)
      <<~HTML
        <div class="head">
          <div class="brand"><div class="logo">#{initials}</div><div><h1>#{name}</h1><p>#{tagline}</p></div></div>
          <div class="from">#{contact.map { "<p>#{it}</p>" }.join}</div>
        </div>
      HTML
    end

    def addressed(rows, to: HOUSEHOLD)
      <<~HTML
        <div class="meta">
          <div class="to">#{to.map { "<p>#{it}</p>" }.join}</div>
          <table>#{rows.map { |label, value| "<tr><td>#{label}</td><td>#{value}</td></tr>" }.join}</table>
        </div>
      HTML
    end

    def lines(headers, rows, total: nil)
      head = headers.map.with_index { |text, index| "<th#{' class="num"' if index.positive?}>#{text}</th>" }.join
      body = rows.map { |row| "<tr>#{row.map.with_index { |cell, index| "<td#{' class="num"' if index.positive?}>#{cell}</td>" }.join}</tr>" }.join
      total_row = total ? "<tr class=\"total\"><td colspan=\"#{headers.size - 1}\">#{total.first}</td><td class=\"num\">#{total.last}</td></tr>" : ""
      "<table class=\"lines\"><tr>#{head}</tr>#{body}#{total_row}</table>"
    end

    def footer(text)
      "<div class=\"foot\">#{text}</div>"
    end

    def receipt(store:, lines:, address:, items:, tax_rate:, paid_with:, date:, number:, footer_lines: [])
      subtotal = items.sum { |_name, amount| amount }
      tax = (subtotal * tax_rate).round(2)
      body = <<~HTML
        <div class="receipt">
          <div class="c"><h1>#{store}</h1>#{lines.map { "<p>#{it}</p>" }.join}<p>#{address}</p></div>
          <hr>
          <p>#{date}  Reg 02  Trans #{number}</p>
          <hr>
          <table>#{items.map { |name, amount| "<tr><td>#{name}</td><td class=\"r\">#{format("%.2f", amount)}</td></tr>" }.join}</table>
          <hr>
          <table>
            <tr><td>SUBTOTAL</td><td class="r">#{format("%.2f", subtotal)}</td></tr>
            <tr><td>TAX #{(tax_rate * 100).round(2)}%</td><td class="r">#{format("%.2f", tax)}</td></tr>
            <tr class="big"><td>TOTAL</td><td class="r">#{format("%.2f", subtotal + tax)}</td></tr>
            <tr><td>#{paid_with}</td><td class="r">#{format("%.2f", subtotal + tax)}</td></tr>
          </table>
          <hr>
          <div class="c">#{footer_lines.map { "<p>#{it}</p>" }.join}</div>
        </div>
      HTML
      page_html(body, width: "3.4in", height: "#{4.2 + (items.size * 0.2) + (footer_lines.size * 0.18)}in", css: RECEIPT_CSS)
    end
  end
end
