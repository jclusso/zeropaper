require "test_helper"

class Ocr::AITest < ActiveSupport::TestCase
  test "a code block around the whole answer is removed" do
    assert_equal "CUSTOMER #: 53710\nSt. James, NY", Ocr::AI.unfence("```text\nCUSTOMER #: 53710\nSt. James, NY\n```\n")
  end

  test "pages wrapped in code blocks are split and unwrapped" do
    answer = "```markdown\n=== PAGE 1 ===\n```\nInvoice 42\n```\n=== PAGE 2 ===\nTotal $10\n```"

    pages = Ocr::AI.new(Setting.instance, nil).send(:split, answer, [ 3, 4 ])

    assert_equal({ 3 => "Invoice 42", 4 => "Total $10" }, pages)
  end

  test "text without code blocks is unchanged" do
    assert_equal "Plain `code` stays", Ocr::AI.unfence("Plain `code` stays")
  end
end
