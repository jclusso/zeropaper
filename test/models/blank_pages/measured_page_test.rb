require "test_helper"

class BlankPages::MeasuredPageTest < ActiveSupport::TestCase
  setup do
    @front_canvas = PdfFactory.printed
    @front = BlankPages::MeasuredPage.new(@front_canvas.to_gray)
  end

  test "a faint mirror of the front shows through" do
    back = BlankPages::MeasuredPage.new(@front_canvas.mirrored_bleed(level: 140, every_nth_row: 3).to_gray)

    refute back.ink.blank?, "the bleed should carry enough ink to need the front to explain it"
    assert back.shows_through?(@front)
  end

  test "a second copy of the same form does not show through" do
    copy = BlankPages::MeasuredPage.new(@front_canvas.to_gray)

    refute copy.shows_through?(@front)
  end

  test "a faint unmirrored copy is not bleed-through" do
    faint_copy = PdfFactory::Canvas.new(400, 520)
    @front_canvas.pixels.each_with_index { |value, index| faint_copy.pixels[index] = 140 if value < 155 && (index / 400 % 3).zero? }

    refute BlankPages::MeasuredPage.new(faint_copy.to_gray).shows_through?(@front)
  end

  test "nothing shows through from a blank front" do
    back = BlankPages::MeasuredPage.new(@front_canvas.mirrored_bleed(level: 140, every_nth_row: 3).to_gray)
    blank_front = BlankPages::MeasuredPage.new(PdfFactory.blank.to_gray)

    refute back.shows_through?(blank_front)
  end

  test "the mirrored grid matches better than the unmirrored one" do
    back = BlankPages::MeasuredPage.new(@front_canvas.mirrored_bleed(level: 140).to_gray)

    assert_operator back.grid.match(@front.grid, mirrored: true), :>, back.grid.match(@front.grid, mirrored: false)
  end
end
