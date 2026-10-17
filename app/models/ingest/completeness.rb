# Whether a file in the ingest folder has been written to the end, judged by
# the structure its format requires at the end of the file. A scanner saving
# over a network share writes a page at a time and can pause for longer than
# any fixed wait while it reads the next page, so a file that has stopped
# changing is not necessarily finished.
#
# Returns :complete or :incomplete, or nil for formats that have no such
# marker (TIFF, plain text) and so can only be judged by how long they have
# been left alone.
module Ingest
  module Completeness
    CHUNK = 1.megabyte
    # PDF readers accept a little trailing whitespace or padding after %%EOF.
    PDF_TAIL = 1.kilobyte
    # The end of central directory record, then a comment of up to 64 KB.
    ZIP_TAIL = 22 + 65_535
    PNG_END = "IEND\xAE\x42\x60\x82".b

    extend self

    def of(io)
      head = read_at(io, 0, 12)

      if head.start_with?("%PDF-")
        pdf(io)
      elsif head.start_with?("\xFF\xD8\xFF".b)
        jpeg(io)
      elsif head.start_with?("\x89PNG\r\n\x1A\n".b)
        png(io)
      elsif head.start_with?("RIFF") && head[8, 4] == "WEBP"
        webp(io)
      elsif head[4, 4] == "ftyp"
        iso_media(io)
      elsif head.start_with?("PK\x03\x04")
        zip(io)
      end
    end

    private
      def pdf(io)
        status tail(io, PDF_TAIL).include?("%%EOF")
      end

      # The end marker must come after the first scan's header, since an
      # embedded thumbnail, which ends with its own end marker, can come
      # before it. The compressed image data cannot contain the end marker,
      # so any after that point is real. Cameras may add data after it, so
      # the whole remainder is searched, from the end.
      def jpeg(io)
        scan_start = jpeg_scan_start(io)
        return :incomplete unless scan_start

        position = io.size
        while position > scan_start
          start = [ position - CHUNK, scan_start ].max
          # One byte of overlap catches a marker split across chunks.
          return :complete if read_at(io, start, position - start + 1).include?("\xFF\xD9".b)
          position = start
        end
        :incomplete
      end

      # Walks the header segments after the start marker to the first start
      # of scan, and returns where the image data begins.
      def jpeg_scan_start(io)
        offset = 2
        loop do
          marker = read_at(io, offset, 4)
          return if marker.bytesize < 4 || marker.getbyte(0) != 0xFF

          length = marker.byteslice(2, 2).unpack1("n")
          offset += 2 + length
          return offset if marker.getbyte(1) == 0xDA
        end
      end

      def png(io)
        status tail(io, 64).include?(PNG_END)
      end

      # The header holds the size of everything after its first 8 bytes.
      def webp(io)
        status io.size >= read_at(io, 4, 4).unpack1("V") + 8
      end

      # HEIC is a series of boxes, each starting with its size. A finished
      # file ends exactly where its last box does.
      def iso_media(io)
        offset = 0
        while offset < io.size
          header = read_at(io, offset, 16)
          return :incomplete if header.bytesize < 8

          size = header.unpack1("N")
          if size == 1
            return :incomplete if header.bytesize < 16
            size = header.byteslice(8, 8).unpack1("Q>")
          end
          # A size of 0 runs to the end of the file, however much is there.
          return if size == 0
          return :incomplete if size < 8

          offset += size
        end
        status offset == io.size
      end

      # Word and Excel files are zips, which end with a record pointing back
      # at the central directory just before it.
      def zip(io)
        data = tail(io, ZIP_TAIL)
        record = data.rindex("PK\x05\x06")
        return :incomplete unless record

        directory_size, directory_offset = data.byteslice(record + 12, 8).to_s.unpack("VV")
        return :incomplete unless directory_offset
        # Zip64 keeps the real values elsewhere.
        return if directory_offset == 0xFFFFFFFF

        status directory_offset + directory_size == io.size - data.bytesize + record
      end

      def status(complete)
        complete ? :complete : :incomplete
      end

      def tail(io, length)
        start = [ io.size - length, 0 ].max
        read_at(io, start, io.size - start)
      end

      def read_at(io, offset, length)
        io.pread(length, offset)
      rescue EOFError
        "".b
      end
  end
end
