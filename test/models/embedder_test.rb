require "test_helper"
require "rake"

class EmbedderTest < ActiveSupport::TestCase
  # The test files hold "x", so their checksums stand in for the real ones.
  FAKE_CHECKSUMS = Embedder::FILES.index_with { Digest::SHA256.hexdigest("x") }.freeze

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
    fetched = Set.new
    Informers::Utils::Hub.expects(:get_model_file).times(Embedder::FILES.size).with do |model, file, **options|
      fetched << [ model, file, options ]
      place_model_file(file)
    end
    Informers.expects(:pipeline).never

    with_fake_checksums { assert_equal Embedder::FILES, Embedder.download }
    assert Embedder.downloaded?
    assert_equal Embedder::FILES.map { |file| [ Embedder::MODEL, file, { revision: Embedder::REVISION } ] }, fetched.to_a
  end

  test "download holds a file lock so another process cannot write the same files" do
    locked_elsewhere = nil
    Informers::Utils::Hub.stubs(:get_model_file).with do |_model, file|
      place_model_file(file)
      File.open(File.join(@dir, Embedder::LOCK_FILE)) { |other| locked_elsewhere = !other.flock(File::LOCK_EX | File::LOCK_NB) }
      true
    end

    with_fake_checksums { Embedder.download }

    assert locked_elsewhere
  end

  test "a download that leaves files missing fails rather than reporting success" do
    Informers::Utils::Hub.stubs(:get_model_file).returns("path")

    assert_raises(RuntimeError) { with_fake_checksums { Embedder.download } }
    refute Embedder.downloaded?
  end

  test "a truncated file is fetched again" do
    Embedder::FILES.each { |file| place_model_file(file) }
    model = File.join(@dir, Embedder::MODEL, Embedder::REVISION, "onnx/model.onnx")
    File.write(model, "")
    Informers::Utils::Hub.expects(:get_model_file).once.with { |_model, file| file == "onnx/model.onnx" && place_model_file(file) }

    with_fake_checksums { Embedder.download }

    assert Embedder.downloaded?
    assert_equal "x", File.read(model)
  end

  test "a file still damaged after fetching it again fails the download and is removed" do
    Embedder::FILES.each { |file| place_model_file(file) }
    model = File.join(@dir, Embedder::MODEL, Embedder::REVISION, "onnx/model.onnx")
    File.write(model, "")
    Informers::Utils::Hub.expects(:get_model_file).once.with { File.write(model, "truncated") }

    assert_raises(RuntimeError) { with_fake_checksums { Embedder.download } }
    refute Embedder.downloaded?
    refute File.exist?(model)
  end

  test "files present but never verified do not count as downloaded" do
    Embedder::FILES.each { |file| place_model_file(file) }

    refute Embedder.downloaded?
  end

  test "a complete download removes the copy from before the model was pinned and nothing else" do
    folder = File.join(@dir, Embedder::MODEL)
    Embedder::FILES.each do |file|
      FileUtils.mkdir_p(File.dirname(File.join(folder, file)))
      File.write(File.join(folder, file), "old")
    end
    other_model = File.join(@dir, "Other/model/config.json")
    FileUtils.mkdir_p(File.dirname(other_model))
    File.write(other_model, "{}")
    Informers::Utils::Hub.stubs(:get_model_file).with { |_model, file| place_model_file(file) }

    with_fake_checksums { Embedder.download }

    Embedder::FILES.each { |file| refute File.exist?(File.join(folder, file)), file }
    refute Dir.exist?(File.join(folder, "onnx"))
    assert Embedder.downloaded?
    assert File.exist?(other_model)
  end

  test "the worker's download job skips a model that is already there" do
    place_model
    Informers::Utils::Hub.expects(:get_model_file).never

    assert Embedder.downloaded?
    DownloadEmbeddingModelJob.perform_now
  end

  test "a missing model is downloaded by the job" do
    Informers::Utils::Hub.expects(:get_model_file).times(Embedder::FILES.size).with { |_model, file| place_model_file(file) }

    refute Embedder.downloaded?
    with_fake_checksums { DownloadEmbeddingModelJob.perform_now }
    assert Embedder.downloaded?
  end

  test "the download job holds its lock for as long as a slow download takes" do
    assert_equal 1.hour, DownloadEmbeddingModelJob.concurrency_duration
  end

  test "the prefetch task fills MODELS_DIR" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("embedder:prefetch")
    Informers::Utils::Hub.expects(:get_model_file).times(Embedder::FILES.size).with { |_model, file| place_model_file(file) }

    with_fake_checksums { assert_output(/Downloaded/) { Rake::Task["embedder:prefetch"].execute } }
    assert Embedder.downloaded?
  end

  test "embedding without the model fails the step and queues the download instead of fetching it" do
    Informers::Utils::Hub.expects(:get_model_file).never
    Informers.expects(:pipeline).never

    error = assert_raises(Embedder::ModelMissing) { Embedder.send(:run, [ "Lease agreement" ]) }

    assert_match "not finished downloading", error.message
    assert_enqueued_jobs 1, only: DownloadEmbeddingModelJob
  end

  test "the model loads from disk only, at the pinned revision" do
    place_model
    model = ->(texts, **) { texts.map { [ 0.5 ] } }
    Informers.expects(:pipeline).once.with("embedding", Embedder::MODEL, revision: Embedder::REVISION, local_files_only: true).returns(model)

    assert_equal [ [ 0.5 ], [ 0.5 ] ], Embedder.send(:run, [ "one", "two" ])
    assert_equal [ [ 0.5 ] ], Embedder.send(:run, [ "three" ])
  end

  test "threads embedding at once load the model once" do
    place_model
    loads = 0
    Informers.stubs(:pipeline).with { loads += 1; sleep 0.05; true }.returns(->(texts, **) { texts.map { [ 0.5 ] } })

    results = 4.times.map { Thread.new { Embedder.send(:run, [ "text" ]) } }.map(&:value)

    assert_equal 1, loads
    assert_equal [ [ [ 0.5 ] ] ] * 4, results
  end

  private
    def with_fake_checksums(&)
      stub_const(Embedder, :CHECKSUMS, FAKE_CHECKSUMS, &)
    end

    def place_model
      Embedder::FILES.each { |file| place_model_file(file) }
      FileUtils.touch(File.join(@dir, Embedder::MODEL, Embedder::REVISION, Embedder::VERIFIED_FILE))
    end

    def place_model_file(file)
      path = File.join(@dir, Embedder::MODEL, Embedder::REVISION, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "x")
      true
    end
end
