require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the upload page has one drop zone, a folder link and the row template" do
    get new_document_path

    assert_response :success
    assert_select "[data-controller=upload] label[data-upload-target=zone]", count: 1
    # Without `for`, the label would open its first labelable child: the folder button.
    assert_select "label[data-upload-target=zone][for=upload_files]"
    assert_select "input#upload_files[type=file][name='files[]']:not([webkitdirectory])"
    assert_select "input[webkitdirectory][name='files[]']", count: 1
    assert_select "label[data-upload-target=zone] button[data-action='upload#chooseFolder']", text: "Choose a folder"
    assert_select "label[data-upload-target=zone]", text: /Dragging a folder in skips that/
    assert_select "template[data-upload-target=template] li[data-upload-row]"
  end

  test "an upload request returns the outcome for its file" do
    assert_difference -> { Document.count } do
      post documents_path, params: { files: [ upload("bill.txt", DocumentHelpers::BILL_TEXT) ], private: "1" }, as: :multipart, headers: { "Accept" => "application/json" }
    end

    result = response.parsed_body["results"].sole
    document = Document.last
    assert_response :success
    assert_equal "created", result["status"]
    assert_equal document_path(document), result["url"]
    assert result["private"]
    assert_equal "Marked private on upload", document.private_reason
  end

  test "duplicates and unsupported files are reported, not added" do
    post documents_path, params: { files: [ upload("bill.txt", DocumentHelpers::BILL_TEXT) ] }, headers: { "Accept" => "application/json" }

    assert_no_difference -> { Document.count } do
      post documents_path, params: { files: [ upload("copy.txt", DocumentHelpers::BILL_TEXT), upload("program.exe", "MZ\x90\x00binary".b, "application/octet-stream") ] },
        headers: { "Accept" => "application/json" }
    end

    statuses = response.parsed_body["results"].map { |result| result["status"] }
    assert_equal %w[duplicate unsupported], statuses
    assert_equal document_path(Document.last), response.parsed_body["results"].first["url"]
  end

  test "a plain form upload still redirects" do
    post documents_path, params: { files: [ upload("bill.txt", DocumentHelpers::BILL_TEXT) ] }

    assert_redirected_to document_path(Document.last)
  end

  test "library and document pages render" do
    document = document_with_text(DocumentHelpers::BILL_TEXT, title: "March statement")
    document.file.attach(io: StringIO.new(DocumentHelpers::BILL_TEXT), filename: "notes.txt", content_type: "text/plain")

    get documents_path
    assert_response :success
    assert_select "a", text: /March statement/

    get documents_path(view: "timeline")
    assert_response :success

    get document_path(document)
    assert_response :success
    assert_select "h1", text: "March statement"
  end

  test "a multi-page PDF gets the pages dialog, opened on request" do
    document = ingest(text_pdf("Page one has words", "Page two has words", "Page three has words"), filename: "three.pdf")
    document.update!(page_count: 3, status: "ready", page_record: { "map" => [ 1, 2, 3 ], "blank" => [ 2 ] })

    get document_path(document, review: "pages")

    assert_response :success
    assert_select "button[command=show-modal][commandfor=pages-dialog][data-controller=auto-open]"
    assert_select "el-dialog dialog#pages-dialog turbo-frame[id=?][src=?]", dom_id(document, :pages), document_pages_path(document)
  end

  test "a PDF trimmed to one page keeps the pages dialog so its upload can be restored" do
    document = ingest(text_pdf("Page one has words", "Page two has words"), filename: "two.pdf")
    document.update!(page_count: 2, status: "ready")
    document.remove_pages!([ 2 ])
    document.update!(status: "ready")

    get document_path(document)
    assert_select "button[command=show-modal][commandfor=pages-dialog]"
    assert_select "dialog#pages-dialog"

    single = ingest(text_pdf("Only page"), filename: "one.pdf")
    single.update!(page_count: 1, status: "ready")

    get document_path(single)
    assert_select "button[commandfor=pages-dialog]", count: 0
  end

  test "pages turned upright are announced in current page numbers" do
    document = ingest(text_pdf("One", "Two", "Three"), filename: "turned.pdf")
    document.update!(page_count: 2, status: "ready", page_record: { "map" => [ 1, 3 ], "rotated" => { "3" => 180 } })
    document.original_file.attach(io: StringIO.new(text_pdf("One", "Two", "Three")), filename: "turned.pdf", content_type: "application/pdf")

    get document_path(document)

    assert_response :success
    assert_select "p", text: "Page 2 was turned upright."
    assert_select "form[action=?] button", document_original_restoration_path(document), text: "Restore original"
  end

  test "documents with upright pages show no rotation notice" do
    document = ingest(text_pdf("One"), filename: "upright.pdf")
    document.update!(page_count: 1, status: "ready", page_record: { "rotated" => {} })

    get document_path(document)

    assert_response :success
    assert_select "p", text: /turned upright/, count: 0
  end

  test "details use searchable dropdowns and a tag box" do
    document = document_with_text(DocumentHelpers::BILL_TEXT, correspondent: correspondents(:acme_power), tags: [ tags(:utilities) ])

    get document_path(document)

    assert_select "[data-controller=combobox][data-combobox-creatable-value=true] input[type=hidden][name='document[correspondent_name]'][value='Acme Power']"
    assert_select "[data-controller=combobox] input[type=hidden][name='document[document_type_name]']"
    assert_select "[data-controller=chip-input] [data-chip-input-target=token] input[name='document[tag_names][]'][value='Utilities']"
    assert_select "[data-controller=chip-input] el-option[value='Taxes']"
    assert_select "datalist", count: 0
  end

  test "a correspondent and type typed in the dropdown are created and assigned" do
    document = document_with_text("Letter")

    assert_difference -> { Correspondent.count } => 1, -> { DocumentType.count } => 1 do
      patch document_path(document), params: { document: { correspondent_name: "Harbor Dental", document_type_name: "Appointment card", tag_names: [ "" ] } }
    end

    document.reload
    assert_equal "Harbor Dental", document.correspondent.name
    assert_equal "Appointment card", document.document_type.name
    assert_equal "manual", document.metadata_source
  end

  test "saving AI details without changes keeps them from AI" do
    document = document_with_text("Bill", title: nil, original_filename: "scan-0042.pdf", document_date: Date.new(2025, 8, 28),
      correspondent: correspondents(:acme_power), tags: [ tags(:taxes), tags(:utilities) ], metadata_source: "ai", confidence: 0.98)

    patch document_path(document), params: { document: { title: "scan-0042", document_date: "2025-08-28", summary: "",
      correspondent_name: "Acme Power", document_type_name: "", tag_names: [ "", "Utilities", "taxes" ] } }

    document.reload
    assert_equal "ai", document.metadata_source
    assert_in_delta 0.98, document.confidence
    assert_nil document.title

    patch document_path(document), params: { document: { title: "Water bill", tag_names: [ "Utilities", "Taxes" ] } }
    assert_equal "manual", document.reload.metadata_source

    document.update_columns(metadata_source: "ai")
    patch document_path(document), params: { document: { tag_names: [ "Utilities" ] } }
    assert_equal "manual", document.reload.metadata_source
    assert_equal [ "Utilities" ], document.tags.map(&:name)
  end

  test "tags arrive as a list, new names become tags and clearing removes them" do
    document = document_with_text("Letter", tags: [ tags(:taxes) ])

    patch document_path(document), params: { document: { tag_names: [ "", "Utilities", "Car" ] } }
    assert_equal %w[Car Utilities], document.reload.tags.map(&:name).sort

    patch document_path(document), params: { document: { tag_names: [ "" ] } }
    assert_empty document.reload.tags
  end

  test "clearing the correspondent leaves the document without one" do
    document = document_with_text("Letter", correspondent: correspondents(:acme_power))

    patch document_path(document), params: { document: { correspondent_name: "" } }

    assert_nil document.reload.correspondent
  end

  test "library filters are searchable dropdowns that submit on change" do
    get documents_path(correspondent_id: correspondents(:acme_power).id)

    assert_select "[data-controller=combobox] input[type=hidden][name=correspondent_id][value='#{correspondents(:acme_power).id}'][data-action='change->auto-submit#submit']"
    assert_select "[data-controller=combobox] input#filter_correspondent_id[value='Acme Power']"
    assert_select "select", count: 0
  end

  test "types match any chosen one and tags match all chosen ones" do
    receipt = DocumentType.create!(name: "Receipt")
    both = document_with_text("Tax bill", title: "Both tags", document_type: document_types(:invoice), tags: [ tags(:taxes), tags(:utilities) ])
    one = document_with_text("Water bill", title: "One tag", document_type: receipt, tags: [ tags(:utilities) ])
    other = document_with_text("Letter", title: "Other type", tags: [ tags(:utilities) ])

    get documents_path(document_type_ids: [ document_types(:invoice).id, receipt.id ])
    assert_select "a[href='#{document_path(both)}']"
    assert_select "a[href='#{document_path(one)}']"
    assert_select "a[href='#{document_path(other)}']", count: 0

    get documents_path(tag_ids: [ tags(:taxes).id, tags(:utilities).id, "" ])
    assert_select "a[href='#{document_path(both)}']"
    assert_select "a[href='#{document_path(one)}']", count: 0
    assert_select "#filter_tag_ids [data-multi-select-target=summary]", text: "Taxes +1"
    assert_select "input[type=checkbox][name='tag_ids[]'][value='#{tags(:utilities).id}'][checked]"
    assert_select "[data-controller~=multi-select][data-action='multi-select:change->auto-submit#submit']", count: 2
  end

  test "a file over the upload limit is reported, not added" do
    Rails.configuration.x.stubs(:max_upload_bytes).returns(1.megabyte)

    assert_no_difference -> { Document.count } do
      post documents_path, params: { files: [ upload("big.txt", "x" * (1.megabyte + 1)) ] }, as: :multipart, headers: { "Accept" => "application/json" }
    end

    result = response.parsed_body["results"].sole
    assert_equal "too_large", result["status"]
    assert_equal "Larger than the 1 MB upload limit", result["message"]
  end

  test "the upload form knows the limit" do
    get new_document_path

    assert_select "[data-controller=upload][data-upload-max-bytes-value='#{250.megabytes}']"
    assert_select "label[data-upload-target=zone]", text: /up to 250 MB each/
  end

  private
    def upload(filename, content, type = "text/plain")
      Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: filename)
    end
end
