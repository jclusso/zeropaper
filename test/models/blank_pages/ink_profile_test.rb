require "test_helper"

class BlankPages::InkProfileTest < ActiveSupport::TestCase
  test "a white page is blank" do
    profile = BlankPages::InkProfile.measure(PdfFactory.blank.to_gray)

    assert_equal 0.0, profile.ink
    assert profile.blank?
  end

  test "a printed page is not blank" do
    profile = BlankPages::InkProfile.measure(PdfFactory.printed.to_gray)

    assert_operator profile.solid, :>, BlankPages::InkProfile::CONTENT_SOLID
    refute profile.blank?
  end

  test "a few faint marks with nothing near-black are blank" do
    canvas = PdfFactory.blank.rect(100, 100, 12, 8, 120)
    profile = BlankPages::InkProfile.measure(canvas.to_gray)

    assert_operator profile.ink, :>, BlankPages::InkProfile::BLANK_INK
    assert_equal 0.0, profile.solid
    assert profile.blank?
  end

  test "marks in the trimmed margin are ignored" do
    canvas = PdfFactory.blank.rect(0, 0, 400, 15, 0)

    assert BlankPages::InkProfile.measure(canvas.to_gray).blank?
  end

  test "paper is measured against its own median, not pure white" do
    canvas = PdfFactory::Canvas.new(400, 520, paper: 200).rect(100, 100, 12, 8, 150)

    assert BlankPages::InkProfile.measure(canvas.to_gray).blank?
  end
end
