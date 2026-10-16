# Files are only served through controllers that checked the session, and
# never cached by shared proxies.
module FileServing
  extend ActiveSupport::Concern

  private
    def send_attachment(attachment, disposition: :inline)
      response.headers["Cache-Control"] = "private, max-age=3600"
      send_data attachment.download, filename: attachment.filename.to_s, type: attachment.content_type, disposition: disposition
    end

    def send_image(data, type: "image/jpeg")
      response.headers["Cache-Control"] = "private, max-age=86400"
      send_data data, type: type, disposition: :inline
    end
end
