require "test_helper"

# PDF.js renders JBIG2, CCITT fax and JPEG 2000 scans blank without these.
class PdfViewerAssetsTest < ActionDispatch::IntegrationTest
  test "the decoders and fonts PDF.js loads at runtime are served" do
    %w[wasm/jbig2.wasm wasm/jbig2_nowasm_fallback.js wasm/openjpeg.wasm wasm/openjpeg_nowasm_fallback.js
       standard_fonts/FoxitSerif.pfb cmaps/78-H.bcmap].each do |file|
      assert Rails.public_path.join("pdfjs", file).file?, "public/pdfjs/#{file} is missing"
    end
    assert_match %r{wasmUrl: "/pdfjs/wasm/"}, Rails.root.join("app/javascript/controllers/pdf_viewer_controller.js").read
  end
end
