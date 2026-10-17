# A backup or restore whose process died leaves its plain zip of the library
# in tmp/backups. Every boot removes it, as does the next backup or restore.
Rails.application.config.after_initialize { Backup::Scratch.clean }
