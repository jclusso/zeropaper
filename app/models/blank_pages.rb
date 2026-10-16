module BlankPages
  def self.median(histogram, total)
    seen = 0
    histogram.each_with_index do |count, level|
      seen += count
      return level if seen * 2 >= total
    end
    255
  end
end
