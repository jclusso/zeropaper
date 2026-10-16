# Files are only served through controllers that checked the session, and
# never cached by shared proxies.
module FileServing
  extend ActiveSupport::Concern

  private
    # Streams files from the disk service instead of reading them into
    # memory, and answers a single byte range (the PDF viewer asks for
    # these).
    def send_attachment(attachment, disposition: :inline)
      blob = attachment.blob
      options = { filename: blob.filename.to_s, type: blob.content_type, disposition: disposition }
      response.headers["Cache-Control"] = "private, max-age=3600"
      response.headers["Accept-Ranges"] = "bytes"

      if (range = requested_range(blob.byte_size))
        response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{blob.byte_size}"
        send_data blob.download_chunk(range), **options, status: :partial_content
      elsif (path = plain_disk_path(blob))
        send_file path, **options
      else
        send_data blob.download, **options
      end
    end

    def send_image(data, type: "image/jpeg")
      response.headers["Cache-Control"] = "private, max-age=86400"
      send_data data, type: type, disposition: :inline
    end

    def requested_range(size)
      return unless request.headers["Range"]

      ranges = Rack::Utils.get_byte_ranges(request.headers["Range"], size)
      ranges.first if ranges&.one?
    end

    def plain_disk_path(blob)
      blob.service.path_for(blob.key) if blob.service.instance_of?(ActiveStorage::Service::DiskService)
    end
end
