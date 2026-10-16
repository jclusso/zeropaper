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
end
