# Pulls filters out of a search query, locally: dates ("last spring", "March
# 2025", "since 2023"), correspondent and document type names, and tags
# written as #name or "tagged name". What is left is searched as words.
#
#   Search::QueryParser.new("invoices from Acme last spring").call
#   # => keywords: "", filters: { document_type_ids:, correspondent_id:, date_from:, date_to: },
#   #    chips: [ { label: "Type: Invoice", phrase: "invoices" }, ... ]
#
# Phrases listed in `literal` are left as words, which is how removing a chip
# keeps the word without the filter.
class Search::QueryParser
  Chip = Struct.new(:label, :phrase, :keys, keyword_init: true)

  MONTHS = Date::MONTHNAMES.compact.map(&:downcase)
  MONTH_ABBREVIATIONS = Date::ABBR_MONTHNAMES.compact.map(&:downcase)
  MONTH_PATTERN = (MONTHS + MONTH_ABBREVIATIONS).uniq.sort_by(&:length).reverse.join("|")
  SEASONS = { "spring" => [ 3, 5 ], "summer" => [ 6, 8 ], "fall" => [ 9, 11 ], "autumn" => [ 9, 11 ], "winter" => [ 12, 2 ] }.freeze
  LEAD = /(?:(?:from|in|during|on|dated)\s+)?/

  attr_reader :keywords, :filters, :chips

  def initialize(query, literal: [], today: Date.current)
    @query = query.to_s.squish
    @literal = Array(literal).map { |phrase| phrase.to_s.downcase }
    @today = today
  end

  def call
    @text = @query.dup
    @filters = {}
    @chips = []

    find_dates
    find_named(Correspondent, :correspondent_id, "From")
    find_named(DocumentType, :document_type_ids, "Type", plurals: true)
    find_tags

    @keywords = @text.gsub(/\b(?:from|in|during|on|and|dated|tagged)\b\s*$/i, "").squish
    self
  end

  private
    def find_dates
      rules = [
        [ /#{LEAD}\b(today)\b/i, ->(_) { [ @today, @today, "Today" ] } ],
        [ /#{LEAD}\b(yesterday)\b/i, ->(_) { [ @today - 1, @today - 1, "Yesterday" ] } ],
        [ /#{LEAD}\b(?:the\s+)?(last|past)\s+(\d{1,3})\s+(day|week|month|year)s?\b/i, ->(m) { last_n(m[2].to_i, m[3].downcase) } ],
        [ /#{LEAD}\b(this|last)\s+(week|month|year)\b/i, ->(m) { relative_period(m[1].downcase, m[2].downcase) } ],
        [ /#{LEAD}\b(this|last)\s+(spring|summer|fall|autumn|winter)\b/i, ->(m) { relative_season(m[1].downcase, m[2].downcase) } ],
        [ /#{LEAD}\b(spring|summer|fall|autumn|winter)\s+((?:19|20)\d{2})\b/i, ->(m) { season(m[1].downcase, m[2].to_i) } ],
        [ /\b(before|until)\s+(#{MONTH_PATTERN})?\s*((?:19|20)\d{2})\b/i, ->(m) { open_range(:before, m[2], m[3].to_i) } ],
        [ /\b(after|since)\s+(#{MONTH_PATTERN})?\s*((?:19|20)\d{2})\b/i, ->(m) { open_range(:after, m[2], m[3].to_i) } ],
        [ /#{LEAD}\b(#{MONTH_PATTERN})\.?\s+((?:19|20)\d{2})\b/i, ->(m) { month(month_number(m[1]), m[2].to_i) } ],
        [ /#{LEAD}\b((?:19|20)\d{2})\b/i, ->(m) { year(m[1].to_i) } ],
        [ /#{LEAD}\b(#{MONTHS.join("|")})\b/i, ->(m) { recent_month(month_number(m[1])) } ]
      ]

      rules.each do |pattern, build|
        match = @text.match(pattern)
        next unless match && !literal?(match[0])

        from, to, label = build.call(match)
        @filters[:date_from] = from&.iso8601
        @filters[:date_to] = to&.iso8601
        @chips << Chip.new(label: label, phrase: match[0].strip, keys: %w[date_from date_to])
        @text = @text.sub(match[0], " ").squish
        return
      end
    end

    # The longest names first, so "Acme Power" wins over "Acme".
    def find_named(model, key, label, plurals: false)
      model.order(Arel.sql("length(name) desc")).pluck(:id, :name).each do |id, name|
        pattern = /#{LEAD}(?<![[:alnum:]])#{Regexp.escape(name)}#{"s?" if plurals}(?![[:alnum:]])/i
        match = @text.match(pattern)
        next unless match && !literal?(match[0])

        @filters[key] = key.end_with?("_ids") ? [ id ] : id
        @chips << Chip.new(label: "#{label}: #{name}", phrase: match[0].strip, keys: [ key.to_s ])
        @text = @text.sub(match[0], " ").squish
        return
      end
    end

    # Every tag written in the query, each one narrowing the results.
    def find_tags
      Tag.order(Arel.sql("length(name) desc")).pluck(:id, :name).each do |id, name|
        pattern = /(?:#|\btagged\s+)#{Regexp.escape(name)}(?![[:alnum:]])/i
        match = @text.match(pattern)
        next unless match && !literal?(match[0])

        (@filters[:tag_ids] ||= []) << id
        @chips << Chip.new(label: "Tag: #{name}", phrase: match[0].strip, keys: %w[tag_ids])
        @text = @text.sub(match[0], " ").squish
      end
    end

    def literal?(phrase)
      @literal.include?(phrase.strip.downcase)
    end

    def year(value)
      [ Date.new(value, 1, 1), Date.new(value, 12, 31), value.to_s ]
    end

    def month(number, year_value)
      start = Date.new(year_value, number, 1)
      [ start, start.end_of_month, start.strftime("%B %Y") ]
    end

    def recent_month(number)
      year_value = number > @today.month ? @today.year - 1 : @today.year
      month(number, year_value)
    end

    def last_n(count, unit)
      [ @today - count.public_send(unit), @today, "Last #{count} #{unit.pluralize(count)}" ]
    end

    def relative_period(which, unit)
      anchor = which == "last" ? @today - 1.public_send(unit) : @today
      start = anchor.public_send("beginning_of_#{unit}")
      finish = which == "last" ? anchor.public_send("end_of_#{unit}") : @today
      [ start, finish, "#{which.capitalize} #{unit}" ]
    end

    def season(name, year_value)
      first, last = SEASONS.fetch(name)
      start = Date.new(first > last ? year_value - 1 : year_value, first, 1)
      finish = Date.new(year_value, last, 1).end_of_month
      [ start, finish, "#{name.capitalize} #{year_value}" ]
    end

    # "Last spring" is the most recent spring that has ended; "this spring"
    # is the one in the current year.
    def relative_season(which, name)
      _, last = SEASONS.fetch(name)
      ending_year = @today.year
      ending_year += 1 if which == "this" && name == "winter" && @today.month == 12
      if which == "last"
        ending_year -= 1 if Date.new(ending_year, last, 1).end_of_month >= @today
      end
      from, to, = season(name, ending_year)
      [ from, to, "#{which.capitalize} #{name}" ]
    end

    def open_range(direction, month_name, year_value)
      number = month_name.present? ? month_number(month_name) : nil
      if direction == :before
        boundary = number ? Date.new(year_value, number, 1) : Date.new(year_value, 1, 1)
        [ nil, boundary - 1, "Before #{month_name.present? ? boundary.strftime("%B %Y") : year_value}" ]
      else
        boundary = number ? Date.new(year_value, number, 1) : Date.new(year_value, 1, 1)
        [ boundary, nil, "Since #{month_name.present? ? boundary.strftime("%B %Y") : year_value}" ]
      end
    end

    def month_number(name)
      name = name.downcase.delete(".")
      (MONTHS.index(name) || MONTH_ABBREVIATIONS.index(name)) + 1
    end
end
