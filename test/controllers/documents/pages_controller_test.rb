require "test_helper"

class Documents::PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @document = ingest(text_pdf("Page one has words", "Page two has words", "Page three has words"), filename: "three.pdf")
    @document.update!(page_count: 3, status: "ready", page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 2 ] })
  end

  test "the frame preselects suggested blank pages for removal" do
    get document_pages_path(@document), headers: { "Turbo-Frame" => dom_id(@document, :pages) }

    assert_response :success
    assert_select "turbo-frame[id=?]", dom_id(@document, :pages)
    assert_select "input[name='pages[]'][checked]", count: 1
    assert_select "input[name='pages[]'][value='2'][checked]"
    assert_select "form#page-removal-form[data-turbo-frame=_top]"
    assert_select "button[type=submit][form=page-removal-form].btn-danger-solid"
    assert_select "button.btn-primary", count: 0
  end

  test "opened directly it renders inside the page layout" do
    get document_pages_path(@document)

    assert_response :success
    assert_select ".card turbo-frame[id=?]", dom_id(@document, :pages)
  end

  test "removing a page returns to the document" do
    post document_page_removal_path(@document), params: { pages: [ "2" ], version: @document.checksum }

    assert_redirected_to document_path(@document)
    assert_equal 2, @document.reload.page_count
  end
end
