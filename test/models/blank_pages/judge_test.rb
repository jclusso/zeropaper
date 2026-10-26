require "test_helper"

class BlankPages::JudgeTest < ActiveSupport::TestCase
  RESPONSES = "https://api.openai.com/v1/responses".freeze

  setup { configure_openai(blank_page_ai_check: true) }

  test "tells the model which page each image is" do
    front = PdfFactory.printed
    pdf = scanned_pdf(front, front.mirrored_bleed(level: 140, every_nth_row: 3), PdfFactory.printed)
    document = ingest(pdf, filename: "scan.pdf")
    sent = nil
    stub_request(:post, RESPONSES).to_return do |request|
      sent = JSON.parse(request.body)
      { status: 200, body: response_body({ pages: [ { page: 2, blank: true } ] }.to_json), headers: { "Content-Type" => "application/json" } }
    end
    unsure = [ BlankPages::Verdict.new(blank: false, sure: true), BlankPages::Verdict.new(blank: true, sure: false), BlankPages::Verdict.new(blank: false, sure: true) ]

    verdicts = with_pdf_file(pdf) { |path| BlankPages::Judge.new(document).call(path, unsure) }

    parts = sent.fetch("input").flat_map { |message| Array(message["content"]) }
    prompt = parts.filter_map { |part| part["text"] if part["type"] == "input_text" }.join
    assert_match "image 1 is page 1, image 2 is page 2", prompt
    assert_equal 2, parts.count { |part| part["type"] == "input_image" }
    assert_equal [ false, true, false ], verdicts.map(&:blank)
    assert verdicts.all?(&:sure)
  end

  private
    def response_body(text)
      {
        id: "resp_1", object: "response", status: "completed", model: "gpt-5.6-luna",
        output: [ { type: "message", id: "msg_1", status: "completed", role: "assistant", content: [ { type: "output_text", text: text, annotations: [] } ] } ],
        usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 }
      }.to_json
    end
end
