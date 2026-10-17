namespace :documents do
  desc "Fingerprint the pages of every PDF, then check documents not yet flagged for duplicates again"
  task page_hashes: :environment do
    documents = Document.where(status: "ready").order(:created_at)
    documents.find_each(&:record_page_hashes!)

    flagged = documents.where(duplicate_of_id: nil).count do |document|
      document.flag_possible_duplicate.to_s.start_with?("Looks like")
    end
    puts "Fingerprinted #{documents.count} documents, flagged #{flagged} new possible duplicates"
  end
end
