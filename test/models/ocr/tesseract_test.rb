require "test_helper"

class Ocr::TesseractTest < ActiveSupport::TestCase
  test "a failed run removes its temporary directory" do
    dir = Dir.mktmpdir
    Dir.stubs(:mktmpdir).returns(dir)
    Pdf.stubs(:capture).with { |*command, **| File.write(File.join(dir, "text.txt"), "private text") }
      .returns([ "", "boom", stub(success?: false, exitstatus: 2) ])

    assert_raises(Pdf::CommandFailed) do
      Ocr::Tesseract.new(Setting.instance).call("scan.pdf", pages: [ 1 ], content_type: "application/pdf")
    end

    refute Dir.exist?(dir)
  end

  test "a successful run hands the directory with the searchable PDF to the caller" do
    dir = Dir.mktmpdir
    Dir.stubs(:mktmpdir).returns(dir)
    Pdf.stubs(:capture).with { |*command, **| File.write(command.last, "%PDF") && File.write(File.join(dir, "text.txt"), "Page one") }
      .returns([ "", "", stub(success?: true, exitstatus: 0) ])

    result = Ocr::Tesseract.new(Setting.instance).call("scan.pdf", pages: [ 1 ], content_type: "application/pdf")

    assert_equal({ 1 => "Page one" }, result.pages)
    assert File.exist?(result.archive_path)
  ensure
    FileUtils.rm_rf(dir)
  end

  test "straightens pages when the setting is on" do
    assert_includes command_for(mode: :skip), "--deskew"
    assert_includes command_for(mode: :force), "--deskew"
  end

  test "leaves pages as they are when the setting is off" do
    Setting.instance.update!(straighten_pages: false)

    refute_includes command_for(mode: :skip), "--deskew"
  end

  test "reads pages with a scanner's text layer afresh so they can be straightened" do
    command = command_for(mode: :redo)

    assert_includes command, "--deskew"
    assert_includes command, "--force-ocr"
    refute_includes command, "--redo-ocr"
  end

  test "keeps a scanner's page images when straightening is off" do
    Setting.instance.update!(straighten_pages: false)
    command = command_for(mode: :redo)

    assert_includes command, "--redo-ocr"
    refute_includes command, "--deskew"
  end

  test "reads the pages as scanned when they can't be straightened" do
    commands = []
    Pdf.stubs(:capture).with { |*arguments, **| commands << arguments }
      .returns([ "", "SubprocessOutputError", stub(success?: false, exitstatus: 7) ])
      .then.returns([ "", "", stub(success?: true, exitstatus: 0) ])

    Ocr::Tesseract.new(Setting.instance).call("scan.pdf", pages: [ 1 ], content_type: "application/pdf", mode: :redo)

    assert_equal [ true, false ], commands.map { |command| command.include?("--deskew") }
    assert_equal [ "--force-ocr", "--redo-ocr" ], commands.map { |command| command.find { it.end_with?("-ocr") } }
  end

  private
    def command_for(mode:)
      command = nil
      Pdf.stubs(:capture).with { |*arguments, **| command = arguments }.returns([ "", "", stub(success?: true, exitstatus: 0) ])
      Ocr::Tesseract.new(Setting.instance).call("scan.pdf", pages: [ 1 ], content_type: "application/pdf", mode: mode)
      command
    end
end
