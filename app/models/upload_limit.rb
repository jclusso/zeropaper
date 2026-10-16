require "zip"

# How big a file ZeroPaper takes in. Uploads and ingested files are capped at
# MAX_UPLOAD_MB, and zip based files (Word, Excel, export archives) may expand
# to four times that before anything parses them, so a small compressed file
# cannot exhaust memory.
module UploadLimit
  EXPANSION = 4
  CHUNK = 1.megabyte

  class Exceeded < StandardError; end

  extend self

  def max_bytes
    Rails.configuration.x.max_upload_bytes
  end

  def max_megabytes
    max_bytes / 1.megabyte
  end

  def max_expanded_bytes
    max_bytes * EXPANSION
  end

  # Raises Exceeded when the zip at +path+ declares more uncompressed bytes
  # than allowed: in all, or with +each_entry+ in any one entry, for export
  # archives that hold a whole library. rubyzip refuses entries that expand
  # past their declared size, so the declared sizes are a real bound.
  def check_zip!(path, each_entry: false)
    sizes = Zip::File.open(path) { |zip| zip.entries.map(&:size) }
    largest = each_entry ? sizes.max.to_i : sizes.sum
    raise Exceeded, "Unzips to more than the #{max_expanded_bytes / 1.megabyte} MB limit" if largest > max_expanded_bytes
  end

  def sha256(io)
    digest = Digest::SHA256.new
    io.rewind
    while (chunk = io.read(CHUNK))
      digest << chunk
    end
    io.rewind
    digest.hexdigest
  end
end
