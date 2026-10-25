require_relative "templates"

# The fictional library: one household's bills, statements, letters and
# receipts. Each entry has the HTML the file is made from, how it is made
# (a PDF with text, a scanned PDF or a photo), and the details an AI
# provider would have proposed for it.
module Demo
  module Documents
    extend Templates

    Spec = Data.define(:key, :filename, :format, :html, :details, :private, :source, :added_days_ago, :pages, :review) do
      def initialize(key:, filename:, format:, html:, details:, private: false, source: "upload", added_days_ago: 30, pages: nil, review: [])
        super
      end
    end

    module_function

    def all
      [
        *electric_bills,
        electric_bill_rescan,
        water_bill,
        phone_bill,
        *bank_statements,
        auto_renewal,
        claim_letter,
        homeowners_packet,
        dental_invoice,
        dental_reminder,
        visit_summary,
        wage_statement,
        property_tax,
        donation_receipt,
        warranty,
        hardware_receipt,
        grocery_receipt,
        auto_service,
        vet_invoice,
        mortgage_statement,
        flight_receipt,
        internet_offer
      ]
    end

    NORTHWIND = { name: "Northwind Utilities", initials: "NU", tagline: "Electric service for the Brightwater valley",
                  contact: [ "PO Box 0100, Brightwater, ST 00000", "(555) 010-4400", "billing@northwind.example.com" ] }.freeze

    def electric_bills
      [
        [ "2026-07", Date.new(2026, 7, 14), 612, 98.42, 74 ],
        [ "2026-08", Date.new(2026, 8, 13), 784, 124.17, 46 ],
        [ "2026-09", Date.new(2026, 9, 14), 701, 111.63, 16 ]
      ].map do |period, date, kwh, total, ago|
        Spec.new(
          key: "electric-#{period}", filename: "northwind-electric-#{period}.pdf", format: :pdf, added_days_ago: ago,
          html: electric_bill_html(date, kwh, total),
          details: {
            title: "Electric bill #{date.strftime("%B %Y")}", date: date, correspondent: "Northwind Utilities", type: "Utility Bill",
            tags: %w[utilities home], confidence: 0.96,
            summary: "Monthly electric bill from Northwind Utilities for #{kwh} kWh used between #{(date - 31).strftime("%B %-d")} and #{(date - 1).strftime("%B %-d, %Y")}. " \
                     "The amount due is #{money(total)}, paid automatically from the checking account on #{(date + 14).strftime("%B %-d")}."
          }
        )
      end
    end

    USAGE = { 10 => 410, 11 => 455, 12 => 520, 1 => 480, 2 => 445, 3 => 400, 4 => 380, 5 => 430, 6 => 540, 7 => 612, 8 => 784, 9 => 701 }.freeze

    def electric_bill_html(date, kwh, total)
      supply = (kwh * 0.082).round(2)
      delivery = (kwh * 0.048).round(2)
      fees = (total - supply - delivery - 6.95).round(2)
      months = (0..11).map { |back| date.prev_month(11 - back) }
      body = <<~HTML
        <div class="page">
          #{header(**NORTHWIND)}
          #{addressed([ [ "Account", "000-555-0142" ], [ "Bill date", date.strftime("%B %-d, %Y") ], [ "Service period", "#{(date - 31).strftime("%b %-d")} – #{(date - 1).strftime("%b %-d, %Y")}" ], [ "Meter", "NW-000-7731" ] ])}
          <div class="due">
            <div><span>Amount due</span><strong>#{money(total)}</strong></div>
            <div><span>Due date</span><strong>#{(date + 21).strftime("%B %-d, %Y")}</strong></div>
            <div><span>Energy used</span><strong>#{kwh} kWh</strong></div>
          </div>
          <h2>Electric service summary</h2>
          #{lines([ "Charge", "Rate", "Amount" ], [
            [ "Basic service charge", "monthly", money(6.95) ],
            [ "Energy supply", "#{kwh} kWh × $0.082", money(supply) ],
            [ "Delivery", "#{kwh} kWh × $0.048", money(delivery) ],
            [ "State energy fund and taxes", "", money(fees) ]
          ], total: [ "Total current charges", money(total) ])}
          <h3>Your usage, last 12 months</h3>
          <div class="chart">#{months.map { |month| "<i class=\"#{"now" if month == date}\" style=\"height:#{(USAGE[month.month] / 8.0).round}px\"></i>" }.join}</div>
          <div class="months">#{months.map { "<span>#{it.strftime("%b")}</span>" }.join}</div>
          <div class="box"><strong>AutoPay is on.</strong> #{money(total)} will be drawn from your account ending 0000 on #{(date + 14).strftime("%B %-d, %Y")}. No action is needed.</div>
          <p class="small">Summer rates apply June through September. Tip: a ceiling fan set to counter-clockwise lets you raise the thermostat by about 4°F without losing comfort.</p>
          <div class="stub"><div><strong>Northwind Utilities</strong><br>Account 000-555-0142<br>Sam & Alex Rivera</div><div>Amount due <strong>#{money(total)}</strong><br>Due #{(date + 21).strftime("%m/%d/%Y")}<br>AutoPay — do not mail</div></div>
          #{footer("Northwind Utilities is a fictional company used for demonstration. Questions? Call (555) 010-4400, weekdays 8 am – 6 pm.")}
        </div>
      HTML
      page_html(body, accent: "#1d4ed8")
    end

    def electric_bill_rescan
      september = electric_bills.last
      Spec.new(
        key: "electric-2026-09-scan", filename: "scan_0042.pdf", format: :scan_pdf, source: "folder", added_days_ago: 2,
        html: september.html,
        details: september.details.merge(confidence: 0.91),
        pages: 1
      )
    end

    def water_bill
      date = Date.new(2026, 10, 3)
      body = <<~HTML
        <div class="page">
          #{header(name: "City of Brightwater", initials: "CB", tagline: "Water & Sewer Department", contact: [ "1 Civic Plaza, Brightwater, ST 00000", "(555) 010-2200", "water@brightwater.example.com" ])}
          #{addressed([ [ "Account", "WS-000-31877" ], [ "Bill date", date.strftime("%B %-d, %Y") ], [ "Quarter", "July – September 2026" ] ])}
          <div class="due"><div><span>Amount due</span><strong>$186.40</strong></div><div><span>Due date</span><strong>October 31, 2026</strong></div><div><span>Water used</span><strong>14,200 gal</strong></div></div>
          <h2>Quarterly water and sewer bill</h2>
          #{lines([ "Charge", "Usage", "Amount" ], [
            [ "Water base charge", "quarter", "$28.50" ], [ "Water usage", "14,200 gal", "$71.00" ],
            [ "Sewer service", "14,200 gal", "$68.16" ], [ "Stormwater fee", "quarter", "$18.74" ]
          ], total: [ "Total due", "$186.40" ])}
          <div class="box">Lawn watering is limited to Tuesdays and Saturdays before 9 am until November 1.</div>
          #{footer("A fictional municipality used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "water", filename: "brightwater-water-q3-2026.pdf", format: :pdf, added_days_ago: 21,
        html: page_html(body, accent: "#0369a1"),
        details: { title: "Water & sewer bill Q3 2026", date: date, correspondent: "City of Brightwater", type: "Utility Bill", tags: %w[utilities home], confidence: 0.94,
                   summary: "Quarterly water and sewer bill for July through September 2026: 14,200 gallons used, $186.40 due by October 31, 2026. Includes a reminder about watering restrictions until November 1." }
      )
    end

    def phone_bill
      date = Date.new(2026, 9, 22)
      body = <<~HTML
        <div class="page">
          #{header(name: "Velocity Wireless", initials: "VW", tagline: "Unlimited family plan", contact: [ "(555) 010-8800", "help@velocity.example.com" ])}
          #{addressed([ [ "Account", "VW-000-55021" ], [ "Statement date", date.strftime("%B %-d, %Y") ], [ "Billing period", "Aug 22 – Sep 21, 2026" ] ])}
          <div class="due"><div><span>Total due</span><strong>$142.38</strong></div><div><span>Due date</span><strong>October 12, 2026</strong></div></div>
          <h2>Your lines</h2>
          #{lines([ "Line", "Plan", "Amount" ], [
            [ "Sam (555) 010-0141", "Unlimited Plus", "$45.00" ], [ "Alex (555) 010-0142", "Unlimited Plus", "$45.00" ],
            [ "Tablet (555) 010-0143", "Data 10 GB", "$15.00" ], [ "Device payment 14 of 24", "Phone", "$27.08" ],
            [ "Taxes and fees", "", "$10.30" ]
          ], total: [ "Total", "$142.38" ])}
          #{footer("Velocity Wireless is a fictional carrier used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "phone", filename: "velocity-statement-sep-2026.pdf", format: :pdf, added_days_ago: 31,
        html: page_html(body, accent: "#7c3aed"),
        details: { title: "Mobile phone bill September 2026", date: date, correspondent: "Velocity Wireless", type: "Utility Bill", tags: %w[utilities], confidence: 0.93,
                   summary: "Velocity Wireless family plan statement for August 22 to September 21, 2026, covering two phones and a tablet. Total due is $142.38 by October 12, including device payment 14 of 24." }
      )
    end

    def bank_statements
      [ [ Date.new(2026, 8, 31), 6_214.55, 5_870.12, 23 ], [ Date.new(2026, 9, 30), 5_870.12, 6_402.88, 20 ] ].map do |date, opening, closing, ago|
        body = <<~HTML
          <div class="page">
            #{header(name: "Bluefin Credit Union", initials: "BF", tagline: "Member-owned since 1952", contact: [ "(555) 010-3300", "bluefin.example.com" ])}
            #{addressed([ [ "Account", "Checking ••••0000" ], [ "Statement period", "#{date.beginning_of_month.strftime("%b %-d")} – #{date.strftime("%b %-d, %Y")}" ] ])}
            <h2>Checking statement</h2>
            <div class="due"><div><span>Opening balance</span><strong>#{money(opening)}</strong></div><div><span>Closing balance</span><strong>#{money(closing)}</strong></div></div>
            #{lines([ "Date", "Description", "Amount" ], [
              [ date.beginning_of_month.strftime("%m/%d"), "Payroll deposit — Copperleaf Studio", "+$3,412.50" ],
              [ (date.beginning_of_month + 3).strftime("%m/%d"), "Oakline Home Loans — mortgage", "−$1,846.20" ],
              [ (date.beginning_of_month + 6).strftime("%m/%d"), "Harbor Mutual Insurance — auto premium", "−$118.75" ],
              [ (date.beginning_of_month + 11).strftime("%m/%d"), "Northwind Utilities — AutoPay", "−$111.63" ],
              [ (date.beginning_of_month + 14).strftime("%m/%d"), "Payroll deposit — Copperleaf Studio", "+$3,412.50" ],
              [ (date.beginning_of_month + 17).strftime("%m/%d"), "Corner Market", "−$86.41" ],
              [ (date.beginning_of_month + 21).strftime("%m/%d"), "Velocity Wireless", "−$142.38" ],
              [ (date.beginning_of_month + 24).strftime("%m/%d"), "Transfer to savings", "−$500.00" ]
            ])}
            #{footer("Bluefin Credit Union is a fictional institution used for demonstration.")}
          </div>
        HTML
        Spec.new(
          key: "bank-#{date.strftime("%Y-%m")}", filename: "bluefin-statement-#{date.strftime("%Y-%m")}.pdf", format: :pdf, added_days_ago: ago,
          html: page_html(body, accent: "#0e7490"),
          details: { title: "Checking statement #{date.strftime("%B %Y")}", date: date, correspondent: "Bluefin Credit Union", type: "Bank Statement", tags: %w[bank], local: true }
        )
      end
    end

    HARBOR = { name: "Harbor Mutual Insurance", initials: "HM", tagline: "Auto · Home · Life",
               contact: [ "200 Pier Road, Brightwater, ST 00000", "(555) 010-7700", "claims@harbormutual.example.com" ] }.freeze

    def auto_renewal
      date = Date.new(2026, 9, 2)
      body = <<~HTML
        <div class="page">
          #{header(**HARBOR)}
          #{addressed([ [ "Policy", "HMA-000-448-21" ], [ "Notice date", date.strftime("%B %-d, %Y") ], [ "Policy term", "Oct 1, 2026 – Apr 1, 2027" ] ])}
          <h2>Auto policy renewal — declarations</h2>
          <p>Your auto policy renews on October 1, 2026. Your six-month premium is <strong>$712.50</strong>, up $38.40 from the last term, mainly because of higher repair costs in your area.</p>
          #{lines([ "Coverage", "Limit", "Premium" ], [
            [ "Bodily injury liability", "$100,000 / $300,000", "$214.20" ], [ "Property damage", "$100,000", "$121.80" ],
            [ "Collision", "$500 deductible", "$198.60" ], [ "Comprehensive", "$250 deductible", "$86.40" ],
            [ "Uninsured motorist", "$100,000 / $300,000", "$61.50" ], [ "Roadside assistance", "included", "$30.00" ]
          ], total: [ "Six-month premium", "$712.50" ])}
          <div class="box"><strong>Vehicle:</strong> 2021 compact hatchback, VIN ending 0000. <strong>Drivers:</strong> Sam Rivera, Alex Rivera. Paid monthly at $118.75.</div>
          <p class="small">A safe-driver discount of 12% is already applied.</p>
          #{footer("Harbor Mutual Insurance is a fictional insurer used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "auto-renewal", filename: "harbor-auto-renewal-2026.pdf", format: :pdf, added_days_ago: 53,
        html: page_html(body, accent: "#b45309"),
        details: { title: "Auto policy renewal Oct 2026", date: date, correspondent: "Harbor Mutual Insurance", type: "Insurance Policy", tags: %w[insurance car], confidence: 0.95,
                   summary: "Harbor Mutual auto policy HMA-000-448-21 renews October 1, 2026 for six months at $712.50, up $38.40 from the last term. Collision has a $500 deductible and comprehensive $250; paid monthly at $118.75." }
      )
    end

    def claim_letter
      date = Date.new(2026, 5, 19)
      body = <<~HTML
        <div class="page">
          #{header(**HARBOR)}
          #{addressed([ [ "Claim", "CL-000-90317" ], [ "Policy", "HMA-000-448-21" ], [ "Date", date.strftime("%B %-d, %Y") ] ])}
          <h2>Claim settlement</h2>
          <p>Dear Sam Rivera,</p>
          <p>We have finished reviewing your claim for the hail damage to your vehicle reported on April 28, 2026. The repair estimate from Pinecrest Auto Service came to $2,340.00. After your $250 comprehensive deductible, we are paying <strong>$2,090.00</strong>.</p>
          <p>The payment was sent by direct deposit to your account ending 0000 today and should arrive within two business days. This claim does not affect your safe-driver discount.</p>
          #{lines([ "Item", "", "Amount" ], [ [ "Approved repair estimate", "", "$2,340.00" ], [ "Comprehensive deductible", "", "−$250.00" ] ], total: [ "Settlement paid", "$2,090.00" ])}
          <p>If you find more damage during the repair, ask the shop to send us a supplement before doing the work.</p>
          <div class="sig"><p>Sincerely,</p><p class="name">Dana Whitlock</p><p>Dana Whitlock, Claims Adjuster</p></div>
          #{footer("Harbor Mutual Insurance is a fictional insurer used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "claim", filename: "harbor-claim-CL-000-90317.pdf", format: :pdf, added_days_ago: 158,
        html: page_html(body, accent: "#b45309"),
        details: { title: "Hail damage claim settlement", date: date, correspondent: "Harbor Mutual Insurance", type: "Letter", tags: %w[insurance car], confidence: 0.92,
                   summary: "Harbor Mutual settled claim CL-000-90317 for hail damage reported April 28, 2026. The $2,340.00 repair estimate less the $250 deductible was paid by direct deposit: $2,090.00." }
      )
    end

    def homeowners_packet
      date = Date.new(2026, 6, 1)
      page_one = <<~HTML
        <div class="page">
          #{header(**HARBOR)}
          #{addressed([ [ "Policy", "HMH-000-120-77" ], [ "Effective", "June 1, 2026 – June 1, 2027" ] ])}
          <h2>Homeowners policy declarations</h2>
          #{lines([ "Coverage", "Limit", "" ], [
            [ "A — Dwelling", "$385,000", "" ], [ "B — Other structures", "$38,500", "" ], [ "C — Personal property", "$192,500", "" ],
            [ "D — Loss of use", "$77,000", "" ], [ "E — Personal liability", "$300,000", "" ], [ "F — Medical payments", "$5,000", "" ]
          ])}
          <div class="box">All-peril deductible: $1,000. Wind and hail deductible: 1% of Coverage A ($3,850).</div>
          <p>Annual premium: <strong>$1,284.00</strong>, paid through the mortgage escrow account with Oakline Home Loans.</p>
          #{footer("Page 1 of 3 · Harbor Mutual Insurance is a fictional insurer used for demonstration.")}
        </div>
      HTML
      page_three = <<~HTML
        <div class="page">
          <h2>Endorsements</h2>
          <p><strong>Water backup:</strong> covers damage from a backed-up drain or sump pump failure up to $10,000.</p>
          <p><strong>Scheduled personal property:</strong> one engagement ring, appraised value $4,200, no deductible.</p>
          <p><strong>Home office:</strong> business equipment covered up to $5,000.</p>
          <h3>Discounts applied</h3>
          <p>Multi-policy (auto and home) 10% · Monitored alarm 5% · Claims-free 3 years 4%</p>
          #{footer("Page 3 of 3 · Harbor Mutual Insurance is a fictional insurer used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "homeowners", filename: "scan_0039.pdf", format: :scan_pdf, source: "folder", added_days_ago: 4, pages: 3,
        html: page_html(page_one + "<div class=\"page\"></div>" + page_three, accent: "#b45309"),
        details: { title: "Homeowners policy 2026–2027", date: date, correspondent: "Harbor Mutual Insurance", type: "Insurance Policy", tags: %w[insurance home], confidence: 0.9,
                   summary: "Harbor Mutual homeowners policy HMH-000-120-77 for June 1, 2026 to June 1, 2027. Dwelling coverage is $385,000 with a $1,000 deductible; the $1,284.00 annual premium is paid from mortgage escrow. Endorsements cover water backup and a scheduled ring." }
      )
    end

    MAPLE = { name: "Maple Street Dental", initials: "MS", tagline: "Family & cosmetic dentistry",
              contact: [ "18 Maple Street, Brightwater, ST 00000", "(555) 010-6120", "frontdesk@maplestreetdental.example.com" ] }.freeze

    def dental_invoice
      date = Date.new(2026, 8, 27)
      body = <<~HTML
        <div class="page">
          #{header(**MAPLE)}
          #{addressed([ [ "Invoice", "MSD-000-2291" ], [ "Date", date.strftime("%B %-d, %Y") ], [ "Patient", "Alex Rivera" ] ])}
          <h2>Statement of services</h2>
          #{lines([ "Service", "Code", "Fee" ], [
            [ "Periodic oral exam", "D0120", "$68.00" ], [ "Adult cleaning", "D1110", "$124.00" ],
            [ "Bitewing X-rays, four films", "D0274", "$82.00" ], [ "Composite filling, one surface", "D2391", "$186.00" ]
          ], total: [ "Total charges", "$460.00" ])}
          #{lines([ "Payments and adjustments", "", "Amount" ], [ [ "Insurance payment — Sunrise Dental Plan", "", "−$322.00" ], [ "Paid at visit, card ending 0000", "", "−$40.00" ] ], total: [ "Balance due", "$98.00" ])}
          <div class="box">Please pay the remaining <strong>$98.00</strong> by September 30, 2026. Your next cleaning is due in February 2027.</div>
          #{footer("Maple Street Dental is a fictional practice used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "dental-invoice", filename: "maple-street-dental-invoice.pdf", format: :pdf, added_days_ago: 58,
        html: page_html(body, accent: "#be123c"),
        details: { title: "Dental cleaning and filling", date: date, correspondent: "Maple Street Dental", type: "Invoice", tags: %w[medical dental], confidence: 0.94,
                   summary: "Maple Street Dental invoice for Alex Rivera's August 27, 2026 visit: exam, cleaning, X-rays and one filling totalling $460.00. Insurance paid $322.00 and $40.00 was paid at the visit, leaving $98.00 due by September 30." }
      )
    end

    def dental_reminder
      date = Date.new(2026, 10, 14)
      body = <<~HTML
        <div class="page">
          #{header(**MAPLE)}
          #{addressed([ [ "Date", date.strftime("%B %-d, %Y") ], [ "Patient", "Sam Rivera" ] ])}
          <h2>Time for your checkup</h2>
          <p>Dear Sam,</p>
          <p>Our records show it has been six months since your last cleaning. We have reserved <strong>Thursday, November 12, 2026 at 8:30 am</strong> with Dr. Priya Okafor.</p>
          <p>Please call (555) 010-6120 to confirm or choose another time. Your plan covers two cleanings a year at no cost.</p>
          <div class="sig"><p>See you soon,</p><p>The team at Maple Street Dental</p></div>
          #{footer("Maple Street Dental is a fictional practice used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "dental-reminder", filename: "appointment-reminder.pdf", format: :pdf, added_days_ago: 9,
        html: page_html(body, accent: "#be123c"),
        details: { title: "Checkup reminder Nov 12", date: date, correspondent: "Maple Street Dental", type: "Letter", tags: %w[dental], confidence: 0.62,
                   summary: "Maple Street Dental reminds Sam Rivera that a six-month cleaning is due and has reserved Thursday, November 12, 2026 at 8:30 am with Dr. Priya Okafor. Call to confirm." },
        review: %w[low_confidence]
      )
    end

    def visit_summary
      date = Date.new(2026, 9, 9)
      body = <<~HTML
        <div class="page">
          #{header(name: "Riverbend Family Medicine", initials: "RF", tagline: "After-visit summary", contact: [ "(555) 010-9150", "riverbend.example.com" ])}
          #{addressed([ [ "Patient", "Sam Rivera" ], [ "Visit", date.strftime("%B %-d, %Y") ], [ "Provider", "Dr. Elena Marsh" ] ])}
          <h2>Annual physical</h2>
          <p>Blood pressure 118/76. Weight stable. Routine blood work ordered; results will be posted to the patient portal.</p>
          <h3>Follow-up</h3>
          <p>Return in 12 months. Flu vaccine given today, left arm.</p>
          #{footer("Riverbend Family Medicine is a fictional practice used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "visit", filename: "riverbend-visit-summary.pdf", format: :pdf, private: true, added_days_ago: 44,
        html: page_html(body, accent: "#15803d"),
        details: { title: "Annual physical visit summary", date: date, correspondent: "Riverbend Family Medicine", type: "Medical Record", tags: %w[medical], local: true }
      )
    end

    def wage_statement
      date = Date.new(2026, 1, 28)
      body = <<~HTML
        <div class="page">
          #{header(name: "Copperleaf Studio", initials: "CS", tagline: "Payroll department", contact: [ "77 Foundry Lane, Brightwater, ST 00000", "payroll@copperleaf.example.com" ])}
          #{addressed([ [ "Employee", "Alex Rivera" ], [ "Employee ID", "CS-00412" ], [ "Tax year", "2025" ] ], to: [ "Alex Rivera", *Templates::HOUSEHOLD.drop(1) ])}
          <h2>Annual wage and tax statement 2025</h2>
          #{lines([ "Box", "Description", "Amount" ], [
            [ "1", "Wages, tips, other compensation", "$81,650.00" ], [ "2", "Federal income tax withheld", "$9,214.00" ],
            [ "3", "Social security wages", "$88,725.00" ], [ "4", "Social security tax withheld", "$5,500.95" ],
            [ "5", "Medicare wages and tips", "$88,725.00" ], [ "6", "Medicare tax withheld", "$1,286.51" ],
            [ "12a", "Retirement plan contributions (D)", "$7,075.00" ], [ "17", "State income tax", "$3,488.20" ]
          ])}
          <p class="small">Employer ID 00-0000000 (demonstration only). Keep this statement with your tax records.</p>
          #{footer("Copperleaf Studio is a fictional employer used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "wages", filename: "copperleaf-wage-statement-2025.pdf", format: :pdf, added_days_ago: 270,
        html: page_html(body, accent: "#c2410c"),
        details: { title: "2025 wage and tax statement", date: date, correspondent: "Copperleaf Studio", type: "Tax Form", tags: %w[taxes-2025 income], confidence: 0.97,
                   summary: "Alex Rivera's 2025 wage and tax statement from Copperleaf Studio: $81,650.00 in wages, $9,214.00 federal and $3,488.20 state income tax withheld, and $7,075.00 in retirement plan contributions." }
      )
    end

    def property_tax
      date = Date.new(2026, 10, 1)
      body = <<~HTML
        <div class="page">
          #{header(name: "Brightwater County Treasurer", initials: "BC", tagline: "Secured property tax bill 2026–27", contact: [ "1 Civic Plaza, Brightwater, ST 00000", "(555) 010-2050" ])}
          #{addressed([ [ "Parcel", "000-114-027" ], [ "Bill date", date.strftime("%B %-d, %Y") ], [ "Assessed value", "$412,000" ] ])}
          <h2>Property tax bill</h2>
          #{lines([ "Levy", "Rate", "Amount" ], [
            [ "County general", "1.0000%", "$4,120.00" ], [ "Brightwater Unified School District", "0.1420%", "$585.04" ],
            [ "Library district", "0.0310%", "$127.72" ], [ "Mosquito abatement", "flat", "$14.50" ]
          ], total: [ "Annual total", "$4,847.26" ])}
          <div class="due"><div><span>1st installment</span><strong>$2,423.63</strong><br>Due December 10, 2026</div><div><span>2nd installment</span><strong>$2,423.63</strong><br>Due April 10, 2027</div></div>
          <p class="small">Paid from escrow by Oakline Home Loans. Do not pay twice.</p>
          #{footer("A fictional county used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "property-tax", filename: "property-tax-2026-27.pdf", format: :pdf, added_days_ago: 12,
        html: page_html(body, accent: "#4d7c0f"),
        details: { title: "Property tax bill 2026–27", date: date, correspondent: "Brightwater County", type: "Tax Form", tags: %w[taxes-2026 home], confidence: 0.93,
                   summary: "Brightwater County secured property tax bill for parcel 000-114-027 for 2026–27: $4,847.26 on an assessed value of $412,000, due in two installments of $2,423.63 on December 10, 2026 and April 10, 2027. Paid from mortgage escrow." }
      )
    end

    def donation_receipt
      date = Date.new(2025, 12, 18)
      body = <<~HTML
        <div class="page">
          #{header(name: "Brightwater Community Food Bank", initials: "FB", tagline: "Nobody in our valley goes hungry", contact: [ "9 Harvest Way, Brightwater, ST 00000", "give@foodbank.example.com" ])}
          #{addressed([ [ "Receipt", "FB-2025-000881" ], [ "Date", date.strftime("%B %-d, %Y") ] ])}
          <h2>Thank you for your gift</h2>
          <p>Dear Sam and Alex,</p>
          <p>Thank you for your year-end donation of <strong>$500.00</strong>, received on December 18, 2025. Your gift provides about 1,500 meals for neighbors in Brightwater.</p>
          <p>No goods or services were provided in exchange for this contribution. Please keep this letter for your tax records.</p>
          <div class="sig"><p>With gratitude,</p><p class="name">Marcus Bell</p><p>Marcus Bell, Executive Director</p></div>
          #{footer("A fictional charity used for demonstration. Tax ID 00-0000000.")}
        </div>
      HTML
      Spec.new(
        key: "donation", filename: "food-bank-receipt-2025.pdf", format: :pdf, added_days_ago: 300,
        html: page_html(body, accent: "#a16207"),
        details: { title: "Year-end donation receipt", date: date, correspondent: "Brightwater Community Food Bank", type: "Receipt", tags: %w[taxes-2025 donations], confidence: 0.95,
                   summary: "Receipt for a $500.00 donation to the Brightwater Community Food Bank on December 18, 2025. No goods or services were received, so it is fully deductible." }
      )
    end

    def warranty
      date = Date.new(2026, 3, 7)
      body = <<~HTML
        <div class="page">
          #{header(name: "Atlas Appliance", initials: "AA", tagline: "Extended protection plan", contact: [ "(555) 010-5600", "care@atlasappliance.example.com" ])}
          #{addressed([ [ "Certificate", "AT-000-61450" ], [ "Purchase date", date.strftime("%B %-d, %Y") ], [ "Coverage ends", "March 7, 2031" ] ])}
          <h2>Warranty certificate</h2>
          #{lines([ "Product", "Model", "Price" ], [ [ "French-door refrigerator, 26 cu ft, stainless", "AR-2600FD", "$1,899.00" ], [ "Five-year protection plan", "AP-5", "$179.00" ] ])}
          <h3>What is covered</h3>
          <p>Parts and labor for mechanical and electrical failures, including the compressor, ice maker and control board, for five years from the purchase date. Food spoilage up to $250 per claim.</p>
          <h3>How to make a claim</h3>
          <p>Call (555) 010-5600 with your certificate number. A technician visits within three business days.</p>
          <span class="stamp">REGISTERED</span>
          #{footer("Atlas Appliance is a fictional company used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "warranty", filename: "atlas-fridge-warranty.pdf", format: :pdf, added_days_ago: 232,
        html: page_html(body, accent: "#334155"),
        details: { title: "Refrigerator warranty until 2031", date: date, correspondent: "Atlas Appliance", type: "Warranty", tags: %w[home appliances], confidence: 0.96,
                   summary: "Atlas Appliance five-year protection plan AT-000-61450 for the AR-2600FD French-door refrigerator bought March 7, 2026 for $1,899.00. Covers parts, labor and food spoilage up to $250 until March 7, 2031." }
      )
    end

    def hardware_receipt
      Spec.new(
        key: "hardware", filename: "IMG_4417.jpg", format: :scan_jpg, source: "folder", added_days_ago: 27,
        html: receipt(store: "GREENLEAF HARDWARE", lines: [ "Tools · Garden · Paint" ], address: "300 Sample Ave, Brightwater ST 00000",
          items: [ [ "Cordless drill 20V", 89.99 ], [ "Drill bit set 21pc", 18.49 ], [ "Wood screws 2in", 7.29 ], [ "Painter's tape 2pk", 9.98 ], [ "Interior paint 1gal", 38.99 ] ],
          tax_rate: 0.0725, paid_with: "VISA ****0000", date: "09/27/2026 14:22", number: "000418",
          footer_lines: [ "Returns within 90 days", "with receipt.", "Thank you!" ]),
        details: { title: "Greenleaf Hardware drill and paint", date: Date.new(2026, 9, 27), correspondent: "Greenleaf Hardware", type: "Receipt", tags: %w[home receipts], confidence: 0.88,
                   summary: "Greenleaf Hardware receipt from September 27, 2026 for a 20V cordless drill, drill bits, screws, painter's tape and a gallon of interior paint: $177.17 with tax, paid by card. Returns accepted within 90 days." }
      )
    end

    def grocery_receipt
      Spec.new(
        key: "grocery", filename: "IMG_4452.jpg", format: :scan_jpg, source: "folder", added_days_ago: 1,
        html: receipt(store: "CORNER MARKET", lines: [ "Fresh every day" ], address: "5 Sample Ave, Brightwater ST 00000",
          items: [ [ "Bananas", 1.84 ], [ "Sourdough loaf", 5.49 ], [ "Eggs dozen", 4.29 ], [ "Coffee beans 12oz", 11.99 ], [ "Olive oil", 9.49 ], [ "Spinach", 3.99 ], [ "Cheddar", 6.79 ] ],
          tax_rate: 0.0, paid_with: "DEBIT ****0000", date: "10/24/2026 18:05", number: "009120",
          footer_lines: [ "Members saved $4.10" ]),
        details: { title: "Corner Market groceries", date: Date.new(2026, 10, 24), correspondent: "Corner Market", type: "Receipt", tags: %w[receipts], confidence: 0.58,
                   summary: "Grocery receipt from Corner Market on October 24, 2026 for $43.88, paid by debit card." },
        review: %w[low_confidence]
      )
    end

    def auto_service
      date = Date.new(2026, 6, 4)
      body = <<~HTML
        <div class="page">
          #{header(name: "Pinecrest Auto Service", initials: "PA", tagline: "Honest repairs since 1998", contact: [ "410 Sample Road, Brightwater, ST 00000", "(555) 010-3890" ])}
          #{addressed([ [ "Repair order", "RO-000-7714" ], [ "Date", date.strftime("%B %-d, %Y") ], [ "Odometer", "38,412 mi" ] ], to: [ "Sam Rivera", "(555) 010-0141" ])}
          <h2>Repair invoice</h2>
          #{lines([ "Work performed", "Hours", "Amount" ], [
            [ "Hail damage: paintless dent repair, hood and roof", "9.5", "$1,520.00" ], [ "Replace windshield, OEM glass", "2.0", "$640.00" ],
            [ "Recalibrate lane camera", "0.8", "$120.00" ], [ "Shop supplies", "", "$60.00" ]
          ], total: [ "Total", "$2,340.00" ])}
          <p>Insurance claim CL-000-90317 (Harbor Mutual). Customer paid deductible $250.00.</p>
          <p class="small">12 month / 12,000 mile warranty on parts and labor.</p>
          #{footer("Pinecrest Auto Service is a fictional shop used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "auto-service", filename: "scan_0031.pdf", format: :scan_pdf, source: "folder", added_days_ago: 140, pages: 1,
        html: page_html(body, accent: "#166534"),
        details: { title: "Hail damage repair invoice", date: date, correspondent: "Pinecrest Auto Service", type: "Invoice", tags: %w[car insurance], confidence: 0.9,
                   summary: "Pinecrest Auto Service repair order RO-000-7714 from June 4, 2026: dent repair, a new windshield and camera recalibration after hail damage, $2,340.00 in total. Billed to Harbor Mutual claim CL-000-90317; the $250 deductible was paid by Sam." }
      )
    end

    def vet_invoice
      date = Date.new(2026, 7, 16)
      body = <<~HTML
        <div class="page">
          #{header(name: "Evergreen Veterinary Clinic", initials: "EV", tagline: "Caring for Brightwater's pets", contact: [ "(555) 010-4730", "hello@evergreenvet.example.com" ])}
          #{addressed([ [ "Invoice", "EV-000-3392" ], [ "Date", date.strftime("%B %-d, %Y") ], [ "Patient", "Biscuit (canine, 4 yrs)" ] ])}
          <h2>Invoice</h2>
          #{lines([ "Service", "Qty", "Amount" ], [
            [ "Wellness exam", "1", "$65.00" ], [ "Rabies vaccine, 3-year", "1", "$32.00" ], [ "DHPP booster", "1", "$38.00" ],
            [ "Heartworm test", "1", "$48.00" ], [ "Flea and tick chews, 6 months", "1", "$112.00" ]
          ], total: [ "Total paid", "$295.00" ])}
          <p>Next rabies vaccine due July 2029. Next wellness exam due July 2027.</p>
          #{footer("Evergreen Veterinary Clinic is a fictional clinic used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "vet", filename: "evergreen-vet-invoice.pdf", format: :pdf, added_days_ago: 100,
        html: page_html(body, accent: "#047857"),
        details: { title: "Biscuit's annual vet visit", date: date, correspondent: "Evergreen Veterinary Clinic", type: "Invoice", tags: %w[pets], confidence: 0.93,
                   summary: "Evergreen Veterinary Clinic invoice for Biscuit's wellness visit on July 16, 2026: exam, rabies and DHPP vaccines, heartworm test and six months of flea and tick chews, $295.00 paid. Rabies is next due July 2029." }
      )
    end

    def mortgage_statement
      date = Date.new(2026, 10, 15)
      body = <<~HTML
        <div class="page">
          #{header(name: "Oakline Home Loans", initials: "OH", tagline: "Mortgage statement", contact: [ "(555) 010-6400", "oakline.example.com" ])}
          #{addressed([ [ "Loan", "000-882-1934" ], [ "Statement date", date.strftime("%B %-d, %Y") ], [ "Payment due", "November 1, 2026" ] ])}
          <div class="due"><div><span>Amount due</span><strong>$1,846.20</strong></div><div><span>Principal balance</span><strong>$287,412.66</strong></div><div><span>Interest rate</span><strong>4.125%</strong></div></div>
          #{lines([ "Payment breakdown", "", "Amount" ], [ [ "Principal", "", "$522.18" ], [ "Interest", "", "$988.02" ], [ "Escrow (taxes and insurance)", "", "$336.00" ] ], total: [ "Total payment", "$1,846.20" ])}
          <h3>Escrow</h3>
          <p>Escrow balance $2,904.11. Upcoming disbursement: Brightwater County property tax, $2,423.63 on December 10, 2026.</p>
          #{footer("Oakline Home Loans is a fictional lender used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "mortgage", filename: "oakline-statement-2026-10.pdf", format: :pdf, added_days_ago: 6,
        html: page_html(body, accent: "#365314"),
        details: { title: "Mortgage statement October 2026", date: date, correspondent: "Oakline Home Loans", type: "Statement", tags: %w[home], confidence: 0.95,
                   summary: "Oakline Home Loans statement for loan 000-882-1934: $1,846.20 due November 1, 2026, including $336.00 escrow. Principal balance is $287,412.66 at 4.125%; escrow will pay the first property tax installment on December 10." }
      )
    end

    def flight_receipt
      date = Date.new(2026, 4, 2)
      body = <<~HTML
        <div class="page">
          #{header(name: "Kestrel Air", initials: "KA", tagline: "Booking confirmation and receipt", contact: [ "kestrelair.example.com", "(555) 010-1200" ])}
          #{addressed([ [ "Confirmation", "KX0000" ], [ "Booked", date.strftime("%B %-d, %Y") ] ], to: [ "Sam Rivera", "Alex Rivera" ])}
          <h2>Your trip to Lakeport</h2>
          #{lines([ "Flight", "Departs", "Arrives" ], [ [ "KX 214 Brightwater → Lakeport", "Jun 26, 2026 7:40 am", "10:05 am" ], [ "KX 219 Lakeport → Brightwater", "Jul 3, 2026 6:15 pm", "8:42 pm" ] ])}
          #{lines([ "Fare", "", "Amount" ], [ [ "2 adults, economy", "", "$548.00" ], [ "Taxes and fees", "", "$83.40" ], [ "Seat selection", "", "$40.00" ] ], total: [ "Total charged to card ending 0000", "$671.40" ])}
          #{footer("Kestrel Air is a fictional airline used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "flight", filename: "kestrel-receipt-KX0000.pdf", format: :pdf, added_days_ago: 205,
        html: page_html(body, accent: "#0891b2"),
        details: { title: "Flights to Lakeport, summer 2026", date: date, correspondent: "Kestrel Air", type: "Receipt", tags: %w[travel], confidence: 0.94,
                   summary: "Kestrel Air booking KX0000 for Sam and Alex: Brightwater to Lakeport on June 26 and back on July 3, 2026, $671.40 in total including seats." }
      )
    end

    def internet_offer
      date = Date.new(2026, 10, 20)
      body = <<~HTML
        <div class="page">
          #{header(name: "Summit Fiber", initials: "SF", tagline: "Fiber internet for Brightwater", contact: [ "summitfiber.example.com" ])}
          #{addressed([ [ "Date", date.strftime("%B %-d, %Y") ] ])}
          <h2>Fiber is coming to Sample Street</h2>
          <p>Get 1 Gig internet for $55/month for 12 months, with free installation and no contract. Offer ends December 31, 2026.</p>
          #{footer("Summit Fiber is a fictional provider used for demonstration.")}
        </div>
      HTML
      Spec.new(
        key: "offer", filename: "summit-fiber-offer.pdf", format: :pdf, added_days_ago: 3,
        html: page_html(body, accent: "#9333ea"),
        details: { title: "Summit Fiber internet offer", date: date, correspondent: "Summit Fiber", type: "Letter", tags: %w[utilities], confidence: 0.81,
                   summary: "Summit Fiber offers 1 Gig fiber internet on Sample Street for $55 a month for 12 months with free installation and no contract, until December 31, 2026." },
        review: %w[always]
      )
    end
  end
end
