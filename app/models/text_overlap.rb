# How much of the actual text two documents share. Embeddings rate forms
# built from the same template (two inspection reports, two invoices from one
# shop) as near identical, so a duplicate also needs the same wording and the
# same numbers: dates, totals, VINs, account and invoice numbers.
class TextOverlap
  SHINGLE_SIZE = 3
  DUPLICATE_TEXT = 0.8
  DUPLICATE_NUMBERS = 0.75
  # With fewer numbers than this the numbers say little either way.
  MIN_NUMBERS = 3

  def initialize(text, other_text)
    @text = text.to_s
    @other_text = other_text.to_s
  end

  # Share of word runs the two texts have in common, from 0 to 1.
  def text_score
    @text_score ||= jaccard(shingles(@text), shingles(@other_text))
  end

  def number_score
    @number_score ||= jaccard(*number_sets)
  end

  # Numbers in both texts, and numbers in either.
  def number_counts
    a, b = number_sets
    [ (a & b).size, (a | b).size ]
  end

  def duplicate?
    text_score >= DUPLICATE_TEXT && (few_numbers? || same_numbers?)
  end

  # Enough numbers on both sides to tell documents apart, and mostly the same.
  def same_numbers?
    numbers? && number_score >= DUPLICATE_NUMBERS
  end

  # Whether both texts have enough numbers for number_score to say anything.
  def numbers?
    !few_numbers?
  end

  private
    def few_numbers?
      number_sets.any? { |set| set.size < MIN_NUMBERS }
    end

    def shingles(text)
      words = text.downcase.scan(/[[:alnum:]]+/)
      return words.to_set if words.size < SHINGLE_SIZE

      words.each_cons(SHINGLE_SIZE).map { |run| run.join(" ") }.to_set
    end

    def number_sets
      @number_sets ||= [ @text, @other_text ].map do |text|
        text.downcase.scan(/[[:alnum:]]*\d[[:alnum:]]*/).select { |token| token.length >= 3 }.to_set
      end
    end

    def jaccard(a, b)
      return 0.0 if a.empty? || b.empty?

      (a & b).size.fdiv((a | b).size)
    end
end
