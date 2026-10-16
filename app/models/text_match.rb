# Case-insensitive, whole-word text matching shared by auto-matching and rules.
module TextMatch
  extend self

  def phrase?(text, phrase)
    return false if text.blank? || phrase.blank?

    text.match?(/(?<![[:alnum:]])#{Regexp.escape(phrase.strip)}(?![[:alnum:]])/i)
  end

  def words(value)
    value.to_s.split(/[\s,]+/).compact_blank
  end

  def any?(text, value)
    words(value).any? { |word| phrase?(text, word) }
  end

  def all?(text, value)
    words = words(value)
    words.any? && words.all? { |word| phrase?(text, word) }
  end

  def regex?(text, pattern)
    return false if text.blank? || pattern.blank?

    Regexp.new(pattern, Regexp::IGNORECASE, timeout: 1).match?(text)
  rescue RegexpError, Regexp::TimeoutError
    false
  end
end
