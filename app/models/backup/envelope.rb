# The encrypted backup file:
#
#   ZPBACKUP              magic
#   u32 + JSON header     version, made_at, key id and nonce prefix; readable
#                         without the key and authenticated with every chunk
#   chunks                u32 length, AES-256-GCM ciphertext, 16 byte tag
#
# The first chunk is the metadata (who made it, document counts), the rest
# the zip in 1 MB pieces. A chunk's nonce is the prefix plus its number and
# its additional data is the header plus whether it is the last chunk, so
# chunks cannot be swapped, dropped or cut off without the read failing.
class Backup::Envelope
  MAGIC = "ZPBACKUP".b.freeze
  VERSION = 1
  CHUNK_SIZE = 1.megabyte
  TAG_SIZE = 16
  NONCE_SIZE = 8
  MAX_HEADER_SIZE = 4.kilobytes
  # Far below the 32 bit counter in the nonce, so it never wraps.
  MAX_CHUNKS = 2**31

  class Invalid < Archive::Reader::InvalidArchive; end

  def self.backup?(path)
    File.binread(path, MAGIC.bytesize) == MAGIC
  end

  def self.seal(plain_path, out, **options)
    new(nil).seal(plain_path, out, **options)
  end

  def self.max_chunks
    MAX_CHUNKS
  end

  def initialize(path)
    @path = path
  end

  # Encrypts the zip at plain_path into out.
  def seal(plain_path, out, key:, made_at:, metadata:)
    use_header({ version: VERSION, made_at: made_at.iso8601, key_id: Backup::Key.id(key),
                 nonce: Base64.strict_encode64(SecureRandom.random_bytes(NONCE_SIZE)) }.to_json.b)
    out.write(MAGIC, [ @header_bytes.bytesize ].pack("N"), @header_bytes)

    write_chunk(out, key, 0, metadata.to_json, false)
    File.open(plain_path, "rb") do |zip|
      counter = 1
      chunk = zip.read(CHUNK_SIZE).to_s
      while (following = zip.read(CHUNK_SIZE))
        write_chunk(out, key, counter, chunk, false)
        counter += 1
        chunk = following
      end
      write_chunk(out, key, counter, chunk, true)
    end
  end

  def header
    open { |io| read_header(io) } unless @header
    @header
  end

  def made_at
    header
    @made_at
  end

  def key_id
    header["key_id"]
  end

  def metadata(key)
    open do |io|
      read_header(io)
      JSON.parse(read_chunk(io, key, 0).first)
    end
  end

  # Decrypts the zip into out, or into nothing to only check every chunk.
  # Stops past +limit+ bytes, since a backup made with another key may be
  # anyone's.
  def decrypt(key, out = nil, limit: UploadLimit.max_backup_bytes)
    open do |io|
      read_header(io)
      read_chunk(io, key, 0)
      size = 0
      (1..).each do |counter|
        data, final = read_chunk(io, key, counter)
        size += data.bytesize
        raise Invalid, "This backup is larger than the #{limit.to_fs(:human_size)} backup limit (MAX_BACKUP_GB)." if size > limit

        out&.write(data)
        break if final
      end
    end
  end

  private
    # Reads the file only through a handle that is still the file it was
    # when checked, so one swapped for a link is not followed.
    def open(&)
      Backup.open_file(@path, &)
    end

    def use_header(bytes)
      @header_bytes = bytes
      @header = JSON.parse(bytes)
      @made_at = Time.iso8601(@header["made_at"]).in_time_zone
      @nonce = Base64.strict_decode64(@header["nonce"])
    end

    # The header is read before the key is checked, so it is checked for
    # shape here: a listing or an upload refuses a damaged one. A date in
    # the future is allowed, since another machine's clock may be ahead;
    # pruning leaves such backups alone.
    def read_header(io)
      raise Invalid, "This is not a ZeroPaper backup." unless io.read(MAGIC.bytesize) == MAGIC

      length = io.read(4)&.unpack1("N")
      raise Invalid, "This backup is damaged." unless length && length <= MAX_HEADER_SIZE

      bytes = io.read(length).to_s
      header = JSON.parse(bytes) if bytes.bytesize == length
      raise Invalid, "This backup is damaged." unless valid_header?(header)
      raise Invalid, "This backup is from a newer ZeroPaper." if header["version"] > VERSION

      use_header(bytes)
      raise Invalid, "This backup is damaged." unless @nonce.bytesize == NONCE_SIZE
    rescue JSON::ParserError, ArgumentError
      raise Invalid, "This backup is damaged."
    end

    def valid_header?(header)
      header.is_a?(Hash) && header["version"].is_a?(Integer) && header["version"].positive? &&
        header["made_at"].is_a?(String) && header["key_id"].is_a?(String) && header["key_id"].match?(/\A\h{8}\z/) &&
        header["nonce"].is_a?(String)
    end

    # The last chunk is the one the file ends with; a file cut short after
    # any other chunk fails because that chunk was sealed as not final.
    def read_chunk(io, key, counter)
      raise Invalid, "This backup needs the key it was made with (#{key_id})." unless Backup::Key.id(key) == key_id
      raise Invalid, "This backup has more chunks than a backup can." if counter > self.class.max_chunks

      length = io.read(4)&.unpack1("N")
      raise Invalid, "This backup is cut short." unless length && length <= CHUNK_SIZE + 1.kilobyte

      ciphertext = io.read(length).to_s
      tag = io.read(TAG_SIZE).to_s
      raise Invalid, "This backup is cut short." unless ciphertext.bytesize == length && tag.bytesize == TAG_SIZE

      final = io.eof?
      [ crypt(:decrypt, key, counter, ciphertext, final, tag), final ]
    rescue OpenSSL::Cipher::CipherError
      raise Invalid, "This backup is damaged or was changed."
    end

    def write_chunk(out, key, counter, data, final)
      raise Invalid, "The library is too large for one backup." if counter > self.class.max_chunks

      ciphertext, tag = crypt(:encrypt, key, counter, data, final)
      out.write([ ciphertext.bytesize ].pack("N"), ciphertext, tag)
    end

    def crypt(direction, key, counter, data, final, tag = nil)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").public_send(direction)
      cipher.key = key
      cipher.iv = @nonce + [ counter ].pack("N")
      cipher.auth_tag = tag if tag
      cipher.auth_data = @header_bytes + (final ? "\x01" : "\x00")
      result = data.empty? ? +"" : cipher.update(data)
      result << cipher.final
      direction == :encrypt ? [ result, cipher.auth_tag ] : result
    end
end
