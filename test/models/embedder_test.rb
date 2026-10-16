require "test_helper"

class EmbedderTest < ActiveSupport::TestCase
  test "download fetches each model file into the cache without loading the model" do
    Embedder::FILES.each { |file| Informers::Utils::Hub.expects(:get_model_file).with(Embedder::MODEL, file).returns("path") }
    Informers.expects(:pipeline).never

    assert_equal Embedder::FILES, Embedder.download
  end

  test "the worker's download job skips a model that is already there" do
    Dir.mktmpdir do |dir|
      Informers.stubs(:cache_dir).returns(dir)
      Embedder::FILES.each do |file|
        path = File.join(dir, Embedder::MODEL, file)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "x")
      end
      Informers::Utils::Hub.expects(:get_model_file).never

      assert Embedder.downloaded?
      DownloadEmbeddingModelJob.perform_now
    end
  end

  test "a missing model is downloaded by the job" do
    Dir.mktmpdir do |dir|
      Informers.stubs(:cache_dir).returns(dir)
      Informers::Utils::Hub.expects(:get_model_file).times(Embedder::FILES.size)

      refute Embedder.downloaded?
      DownloadEmbeddingModelJob.perform_now
    end
  end
end
