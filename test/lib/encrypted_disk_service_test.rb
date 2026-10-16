require "test_helper"

class EncryptedDiskServiceTest < ActiveSupport::TestCase
  setup do
    @service = ActiveStorage::Blob.services.fetch(:test_private)
    @key = SecureRandom.base58(24)
    @data = "Account 12345678, balance $9,876.54\n" * 20
  end

  teardown { @service.delete(@key) }

  test "stores ciphertext and reads back plaintext" do
    @service.upload(@key, StringIO.new(@data), checksum: OpenSSL::Digest::MD5.base64digest(@data))

    on_disk = File.binread(@service.path_for(@key))
    refute_includes on_disk, "Account 12345678"
    assert_equal @data, @service.download(@key)
  end

  test "streams and reads ranges of the plaintext" do
    @service.upload(@key, StringIO.new(@data))

    streamed = +""
    @service.download(@key) { |chunk| streamed << chunk }
    assert_equal @data, streamed
    assert_equal @data.byteslice(8, 8), @service.download_chunk(@key, 8...16)
  end

  test "rejects data that does not match its checksum" do
    assert_raises(ActiveStorage::IntegrityError) do
      @service.upload(@key, StringIO.new(@data), checksum: OpenSSL::Digest::MD5.base64digest("other"))
    end
  end

  test "refuses tampered files" do
    @service.upload(@key, StringIO.new(@data))
    path = @service.path_for(@key)
    bytes = File.binread(path)
    bytes.setbyte(bytes.bytesize - 1, bytes.getbyte(bytes.bytesize - 1) ^ 1)
    File.binwrite(path, bytes)

    assert_raises(OpenSSL::Cipher::CipherError) { @service.download(@key) }
  end

  test "a missing file raises FileNotFoundError" do
    assert_raises(ActiveStorage::FileNotFoundError) { @service.download("missing-#{@key}") }
  end
end
