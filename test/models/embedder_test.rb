require "test_helper"
require "rake"

class EmbedderTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    Informers.stubs(:cache_dir).returns(@dir)
    Embedder.instance_variable_set(:@pipeline, nil)
  end

  teardown do
    Embedder.instance_variable_set(:@pipeline, nil)
    FileUtils.remove_entry(@dir)
  end

  test "download fetches each model file at the pinned revision without loading the model" do
    Embedder::FILES.each do |file|
      Informers::Utils::Hub.expects(:get_model_file).with(Embedder::MODEL, file, revision: Embedder::REVISION).with { place_model_file(file) }.returns("path")
    end
    Informers.expects(:pipeline).never

    assert_equal Embedder::FILES, Embedder.download
    assert Embedder.downloaded?
  end

  test "download holds a file lock so another process cannot write the same files" do
    locked_elsewhere = nil
    Informers::Utils::Hub.stubs(:get_model_file).with do |_model, file|
      place_model_file(file)
      File.open(File.join(@dir, Embedder::LOCK_FILE)) { |other| locked_elsewhere = !other.flock(File::LOCK_EX | File::LOCK_NB) }
      true
    end

    Embedder.download

    assert locked_elsewhere
  end

  test "a download that leaves files missing fails rather than reporting success" do
    Informers::Utils::Hub.stubs(:get_model_file).returns("path")

    assert_raises(RuntimeError) { Embedder.download }
    refute Embedder.downloaded?
  end

  test "the worker's download job skips a model that is already there" do
    Embedder::FILES.each { |file| place_model_file(file) }
    Informers::Utils::Hub.expects(:get_model_file).never

    assert Embedder.downloaded?
    DownloadEmbeddingModelJob.perform_now
  end

  test "a missing model is downloaded by the job" do
    Informers::Utils::Hub.expects(:get_model_file).times(Embedder::FILES.size).with { |_model, file| place_model_file(file) }

    refute Embedder.downloaded?
    DownloadEmbeddingModelJob.perform_now
    assert Embedder.downloaded?
  end

  test "the prefetch task fills MODELS_DIR" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("embedder:prefetch")
    Informers::Utils::Hub.expects(:get_model_file).times(Embedder::FILES.size).with { |_model, file| place_model_file(file) }

    assert_output(/Downloaded/) { Rake::Task["embedder:prefetch"].execute }
    assert Embedder.downloaded?
  end

  test "embedding without the model fails the step and queues the download instead of fetching it" do
    Informers::Utils::Hub.expects(:get_model_file).never
    Informers.expects(:pipeline).never

    error = assert_raises(Embedder::ModelMissing) { Embedder.send(:run, [ "Lease agreement" ]) }

    assert_match "Retry", error.message
    assert_enqueued_jobs 1, only: DownloadEmbeddingModelJob
  end

  test "the model loads from disk only, at the pinned revision" do
    Embedder::FILES.each { |file| place_model_file(file) }
    model = ->(texts, **) { texts.map { [ 0.5 ] } }
    Informers.expects(:pipeline).once.with("embedding", Embedder::MODEL, revision: Embedder::REVISION, local_files_only: true).returns(model)

    assert_equal [ [ 0.5 ], [ 0.5 ] ], Embedder.send(:run, [ "one", "two" ])
    assert_equal [ [ 0.5 ] ], Embedder.send(:run, [ "three" ])
  end

  test "threads embedding at once load the model once" do
    Embedder::FILES.each { |file| place_model_file(file) }
    loads = 0
    Informers.stubs(:pipeline).with { loads += 1; sleep 0.05; true }.returns(->(texts, **) { texts.map { [ 0.5 ] } })

    results = 4.times.map { Thread.new { Embedder.send(:run, [ "text" ]) } }.map(&:value)

    assert_equal 1, loads
    assert_equal [ [ [ 0.5 ] ] ] * 4, results
  end

  private
    def place_model_file(file)
      path = File.join(@dir, Embedder::MODEL, Embedder::REVISION, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "x")
      true
    end
end
