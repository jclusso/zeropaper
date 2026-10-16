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
