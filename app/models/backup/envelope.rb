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

  class Invalid < Archive::Reader::InvalidArchive; end

  def self.backup?(path)
    File.binread(path, MAGIC.bytesize) == MAGIC
  end

  def self.seal(plain_path, out, **options)
    new(nil).seal(plain_path, out, **options)
  end

  def initialize(path)
    @path = path
  end

  # Encrypts the zip at plain_path into out.
  def seal(plain_path, out, key:, made_at:, metadata:)
    use_header({ version: VERSION, made_at: made_at.iso8601, key_id: Backup::Key.id(key),
                 nonce: Base64.strict_encode64(SecureRandom.random_bytes(8)) }.to_json.b)
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
    File.open(@path, "rb") { |io| read_header(io) } unless @header
    @header
  end

  def made_at
    Time.zone.parse(header["made_at"].to_s)
  end

  def key_id
    header["key_id"]
  end

  def metadata(key)
    File.open(@path, "rb") do |io|
      read_header(io)
      JSON.parse(read_chunk(io, key, 0).first)
    end
  end

  # Decrypts the zip into out, or into nothing to only check every chunk.
  def decrypt(key, out = nil)
    File.open(@path, "rb") do |io|
      read_header(io)
      read_chunk(io, key, 0)
      (1..).each do |counter|
        data, final = read_chunk(io, key, counter)
        out&.write(data)
        break if final
      end
    end
  end

  private
    def use_header(bytes)
      @header_bytes = bytes
      @header = JSON.parse(bytes)
    end

    def read_header(io)
      raise Invalid, "This is not a ZeroPaper backup." unless io.read(MAGIC.bytesize) == MAGIC

      length = io.read(4)&.unpack1("N")
      raise Invalid, "This backup is damaged." unless length && length < 4.kilobytes

      use_header(io.read(length).to_s)
      raise Invalid, "This backup is from a newer ZeroPaper." if @header["version"].to_i > VERSION
    rescue JSON::ParserError
      raise Invalid, "This backup is damaged."
    end

    # The last chunk is the one the file ends with; a file cut short after
    # any other chunk fails because that chunk was sealed as not final.
    def read_chunk(io, key, counter)
      raise Invalid, "This backup needs the key it was made with (#{key_id})." unless Backup::Key.id(key) == key_id

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
      ciphertext, tag = crypt(:encrypt, key, counter, data, final)
      out.write([ ciphertext.bytesize ].pack("N"), ciphertext, tag)
    end

    def crypt(direction, key, counter, data, final, tag = nil)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").public_send(direction)
      cipher.key = key
      cipher.iv = Base64.strict_decode64(@header["nonce"]) + [ counter ].pack("N")
      cipher.auth_tag = tag if tag
      cipher.auth_data = @header_bytes + (final ? "\x01" : "\x00")
      result = data.empty? ? +"" : cipher.update(data)
      result << cipher.final
      direction == :encrypt ? [ result, cipher.auth_tag ] : result
    end
end
