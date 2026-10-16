require "test_helper"

class RateLimitsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @document = document_with_text("Lease agreement", title: "Lease")
  end

  test "uploads stop at 60 a minute per user" do
    60.times { |index| post documents_path, params: { files: [ upload("note #{index}.txt") ] }, as: :multipart, headers: { "Accept" => "application/json" } }
    assert_response :success

    post documents_path, params: { files: [ upload("one more.txt") ] }, as: :multipart, headers: { "Accept" => "application/json" }
    assert_response :too_many_requests
    assert_match "Too many uploads", response.parsed_body["error"]

    travel 61.seconds do
      post documents_path, params: { files: [ upload("later.txt") ] }, as: :multipart, headers: { "Accept" => "application/json" }
      assert_response :success
    end
  end

  test "the limit is per user" do
    60.times { |index| post documents_path, params: { files: [ upload("note #{index}.txt") ] }, as: :multipart, headers: { "Accept" => "application/json" } }
    sign_in_as users(:two)

    post documents_path, params: { files: [ upload("mine.txt") ] }, as: :multipart, headers: { "Accept" => "application/json" }
    assert_response :success
  end

  test "Research questions stop at 20 a minute, new conversations and follow ups together" do
    20.times { post conversations_path, params: { question: "How much was the bill?" } }
    conversation = users(:one).conversations.last

    assert_no_difference -> { Message.count } do
      post conversation_messages_path(conversation), params: { question: "And the month before?" }
    end
    assert_redirected_to conversation_path(conversation)
    assert_equal "Too many questions. Wait a minute and ask again.", flash[:alert]
  end

  test "reprocessing and page edits share 30 a minute" do
    15.times { post document_reprocessing_path(@document) }
    15.times { post document_page_removal_path(@document), params: { pages: [] } }

    post document_original_restoration_path(@document)
    assert_redirected_to document_path(@document)
    assert_equal "Too many changes at once. Wait a minute and try again.", flash[:alert]
  end

  test "page images stop at 300 a minute" do
    300.times { get document_page_path(@document, 1) }
    assert_response :not_found

    get document_page_path(@document, 1)
    assert_response :too_many_requests
  end

  private
    def upload(filename)
      Rack::Test::UploadedFile.new(StringIO.new("Note #{filename} #{SecureRandom.hex}"), "text/plain", original_filename: filename)
    end
end
