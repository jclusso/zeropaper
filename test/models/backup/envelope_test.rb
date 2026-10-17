require "test_helper"

class Backup::EnvelopeTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @key = Backup::Key.parse(Backup::Key.generate)
    @plain = File.join(@dir, "plain.zip")
    @data = Random.bytes(2.5.megabytes)
    File.binwrite(@plain, @data)
    @sealed = File.join(@dir, "sealed")
    @made_at = Time.zone.parse("2026-10-16 03:00:00")
    File.open(@sealed, "wb") { |out| Backup::Envelope.seal(@plain, out, key: @key, made_at: @made_at, metadata: { "documents_count" => 3 }) }
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "seals and opens a file of several chunks" do
    envelope = Backup::Envelope.new(@sealed)
    out = StringIO.new("".b)
    envelope.decrypt(@key, out)

    assert_equal @data, out.string
    assert_equal @made_at, envelope.made_at
    assert_equal Backup::Key.id(@key), envelope.key_id
    assert_equal({ "documents_count" => 3 }, envelope.metadata(@key))
    refute_includes File.binread(@sealed), @data.byteslice(0, 64)
  end

  test "another key is refused by its id" do
    other = Backup::Key.parse(Backup::Key.generate)

    error = assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(other) }
    assert_equal "This backup needs the key it was made with (#{Backup::Key.id(@key)}).", error.message
  end

  test "a changed byte is caught" do
    bytes = File.binread(@sealed)
    bytes.setbyte(bytes.bytesize / 2, bytes.getbyte(bytes.bytesize / 2) ^ 1)
    File.binwrite(@sealed, bytes)

    error = assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key) }
    assert_equal "This backup is damaged or was changed.", error.message
  end

  test "a file cut off at a chunk boundary is caught" do
    File.truncate(@sealed, chunk_ends.second)

    assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key) }
  end

  test "a changed header is caught" do
    bytes = File.binread(@sealed)
    bytes.sub!("2026-10-16T03", "2026-10-17T03")
    File.binwrite(@sealed, bytes)

    assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key) }
  end

  test "a file that is not a backup is refused" do
    File.binwrite(@sealed, "PK\x03\x04 not this")

    error = assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).header }
    assert_equal "This is not a ZeroPaper backup.", error.message
  end

  test "reordered chunks are caught" do
    ends = chunk_ends
    bytes = File.binread(@sealed)
    first = bytes.byteslice(ends[0]...ends[1])
    second = bytes.byteslice(ends[1]...ends[2])
    File.binwrite(@sealed, bytes.byteslice(0, ends[0]) + second + first + bytes.byteslice(ends[2]..))

    error = assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key) }
    assert_equal "This backup is damaged or was changed.", error.message
  end

  test "a duplicated chunk is caught" do
    ends = chunk_ends
    bytes = File.binread(@sealed)
    File.binwrite(@sealed, bytes.byteslice(0, ends[1]) + bytes.byteslice(ends[0]...ends[1]) + bytes.byteslice(ends[1]..))

    assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key) }
  end

  test "bytes appended after the last chunk are caught" do
    File.open(@sealed, "ab") { |file| file.write("extra") }

    assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key) }
  end

  test "a whole chunk appended after the last one is caught" do
    ends = chunk_ends
    bytes = File.binread(@sealed)
    File.binwrite(@sealed, bytes + bytes.byteslice(ends[-2]...ends[-1]))

    assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key) }
  end

  test "a malformed header is refused before any chunk is read" do
    good = JSON.parse(File.binread(@sealed).byteslice(12, File.binread(@sealed).byteslice(8, 4).unpack1("N")))
    [ "[1]", "{}", "{", good.merge("made_at" => "yesterday"), good.merge("nonce" => Base64.strict_encode64("1234")), good.merge("key_id" => 1) ].each do |header|
      header = header.to_json unless header.is_a?(String)
      File.binwrite(@sealed, Backup::Envelope::MAGIC + [ header.bytesize ].pack("N") + header)

      error = assert_raises(Backup::Envelope::Invalid, header) { Backup::Envelope.new(@sealed).header }
      assert_equal "This backup is damaged.", error.message
    end

    File.binwrite(@sealed, Backup::Envelope::MAGIC + [ 5.kilobytes ].pack("N") + "x" * 5.kilobytes)
    assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).header }
  end

  test "a wrong key with the same short id is caught" do
    other = Backup::Key.parse(Backup::Key.generate)
    key_id = Backup::Key.id(@key)
    Backup::Key.stubs(:id).returns(key_id)

    error = assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(other) }
    assert_equal "This backup is damaged or was changed.", error.message
  end

  test "an empty payload and one that ends on a chunk boundary both round trip" do
    [ "", Random.bytes(2 * Backup::Envelope::CHUNK_SIZE) ].each do |data|
      File.binwrite(@plain, data)
      File.open(@sealed, "wb") { |out| Backup::Envelope.seal(@plain, out, key: @key, made_at: @made_at, metadata: {}) }
      out = StringIO.new("".b)

      Backup::Envelope.new(@sealed).decrypt(@key, out)

      assert_equal data, out.string
      assert_equal data.empty? ? 2 : 3, chunk_ends.size, "metadata, then the data with no empty chunk after it"
    end
  end

  test "more chunks than the counter allows are refused when sealing and when reading" do
    Backup::Envelope.stubs(:max_chunks).returns(2)

    assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key) }
    error = assert_raises(Backup::Envelope::Invalid) do
      File.open(@sealed, "wb") { |out| Backup::Envelope.seal(@plain, out, key: @key, made_at: @made_at, metadata: {}) }
    end
    assert_equal "The library is too large for one backup.", error.message

    File.binwrite(@plain, Random.bytes(Backup::Envelope::CHUNK_SIZE + 1))
    File.open(@sealed, "wb") { |out| Backup::Envelope.seal(@plain, out, key: @key, made_at: @made_at, metadata: {}) }
    out = StringIO.new("".b)
    Backup::Envelope.new(@sealed).decrypt(@key, out)
    assert_equal File.binread(@plain), out.string
  end

  test "decrypting stops past the whole backup limit" do
    error = assert_raises(Backup::Envelope::Invalid) { Backup::Envelope.new(@sealed).decrypt(@key, limit: 2.megabytes) }

    assert_equal "This backup is larger than the 2 MB backup limit (MAX_BACKUP_GB).", error.message
  end

  private
    # Offsets where each chunk ends.
    def chunk_ends
      File.open(@sealed, "rb") do |io|
        io.read(Backup::Envelope::MAGIC.bytesize)
        io.read(io.read(4).unpack1("N"))
        ends = []
        until io.eof?
          io.seek(io.read(4).unpack1("N") + Backup::Envelope::TAG_SIZE, IO::SEEK_CUR)
          ends << io.pos
        end
        ends
      end
    end
end
