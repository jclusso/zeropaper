module BlankPages
  # An 8-bit grayscale image read from a binary PGM.
  class Gray
    attr_reader :width, :height, :pixels

    def self.read(path)
      data = File.binread(path)
      match = data.match(/\AP5\s+(?:#[^\n]*\n\s*)*(\d+)\s+(\d+)\s+(\d+)\s/)
      raise ArgumentError, "#{path} is not a binary PGM" unless match
      raise ArgumentError, "#{path} is not 8-bit" unless match[3] == "255"

      width, height = match[1].to_i, match[2].to_i
      new(width, height, data.byteslice(match.end(0), width * height).unpack("C*"))
    end

    def initialize(width, height, pixels)
      @width, @height, @pixels = width, height, pixels
    end
  end
end
