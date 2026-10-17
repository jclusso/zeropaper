namespace :backups do
  desc "List backup files in BACKUP_DIR that ZeroPaper has no record of, such as ones copied in by hand"
  task record_existing_files: :environment do
    added = Backup.record_existing_files
    puts "Recorded #{added} #{"backup".pluralize(added)} from #{Backup.folder}"
  rescue Backup::Unreachable => error
    abort error.message
  end
end
