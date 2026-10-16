# AI OCR sometimes wrapped page text in a Markdown code block (```text ... ```).
class RemoveCodeBlocksFromAIText < ActiveRecord::Migration[8.1]
  def up
    Document.where.not(text_source: [ nil, "native", "tesseract", "docling" ]).find_each do |document|
      pages = document.page_texts
      cleaned = pages.map { |text| Ocr::AI.unfence(text).strip }
      document.update_column(:content, cleaned.join(Document::PAGE_BREAK)) if cleaned != pages.map(&:strip)
    end
  end

  def down
  end
end
