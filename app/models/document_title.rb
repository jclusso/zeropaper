# Makes titles consistent no matter where they came from: drops a trailing
# date that only repeats the document's date, then applies title case that
# leaves acronyms and model names ("BMW", "X5", "iPhone") alone.
#
#   DocumentTitle.clean("BMW X5 M service invoice March 2026", date: Date.new(2026, 3, 26))
#   # => "BMW X5 M Service Invoice"
module DocumentTitle
  SMALL_WORDS = %w[a an and as at but by for from in nor of on or per the to vs via with].freeze
  MONTHS = (Date::MONTHNAMES.compact + Date::ABBR_MONTHNAMES.compact).uniq.join("|")

  extend self

  def clean(title, date: nil)
    title = title.to_s.squish
    title = strip_date(title, date) if date
    title_case(title.presence || "").truncate(200).presence
  end

  def title_case(text)
    # An all-caps title (often an OCR'd first line) is cased like any other,
    # keeping short words that are likely acronyms ("IRS", "BMW").
    shouting = text.match?(/[A-Z]{4}/) && !text.match?(/[a-z]/)
    words = text.split(/(\s+)/)
    last = words.rindex { |word| word.match?(/\S/) }
    words.each_with_index.map do |word, index|
      next word if word.match?(/\A\s*\z/)

      first_or_last = index.zero? || index == last
      word = word.downcase if shouting && word.length > 3 && !word.match?(/\d/)
      word = word.downcase if shouting && !first_or_last && SMALL_WORDS.include?(word.downcase)
      word.split(/(?<=-)/).map { |part| cased(part, first_or_last) }.join
    end.join
  end

  private
    # A date at the end that matches the document's date adds nothing, since
    # the date is shown beside the title.
    def strip_date(title, date)
      patterns = [
        /[\s,\-–]+(?:#{date.strftime("%B")}|#{date.strftime("%b")})\.?\s+#{date.day}(?:st|nd|rd|th)?,?\s+#{date.year}\z/i,
        /[\s,\-–]+(?:#{date.strftime("%B")}|#{date.strftime("%b")})\.?\s+#{date.year}\z/i,
        /[\s,\-–]+#{date.iso8601}\z/,
        /[\s,\-–]+#{date.strftime("%m/%d/%Y")}\z/,
        /[\s,\-–]+#{date.strftime("%Y-%m")}\z/
      ]
      stripped = patterns.reduce(title) { |result, pattern| result.sub(pattern, "") }.strip
      # "Statement for March 2026" should not end as "Statement for".
      stripped == title ? title : stripped.sub(/\s+(?:for|from|of|on|in|dated|dt)\z/i, "")
    end

    def cased(word, first_or_last)
      core = word.delete_prefix("(").delete_prefix("“").delete_prefix("\"")
      return word if core.empty?
      # Acronyms, model names and anything already mixed case stay as written.
      return word if core.match?(/\A[^a-z]*[A-Z][^a-z]*[A-Z0-9]/) || core.match?(/[0-9]/) || core.match?(/\A[a-z]+[A-Z]/) || core.match?(/[a-z][A-Z]/)

      lower = word.downcase
      return lower if !first_or_last && SMALL_WORDS.include?(core.downcase.delete_suffix("-").gsub(/[^a-z]/, ""))

      lower.sub(/[[:alpha:]]/, &:upcase)
    end
end
