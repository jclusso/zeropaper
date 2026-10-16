# Where backups and restores keep the plain zip of the library while they
# run: a folder of its own under tmp/backups, removed when the run ends. A
# run that dies leaves its folder behind, so leftovers are removed at boot
# and before every run. A folder in use holds a lock, so one process never
# removes another's.
module Backup::Scratch
  LOCK = ".lock".freeze
  # Long enough for a new folder to take its lock.
  GRACE = 1.minute

  extend self

  def root
    Rails.root.join("tmp/backups")
  end

  def open
    clean
    dir = root.join(SecureRandom.hex(8))
    FileUtils.mkdir_p(dir, mode: 0o700)
    File.open(dir.join(LOCK), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      yield dir
    end
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  # Removes folders whose run has ended.
  def clean
    return unless root.directory?

    root.children.each do |dir|
      next if File.lstat(dir).mtime > GRACE.ago

      lock = dir.join(LOCK)
      if lock.file?
        File.open(lock, File::RDONLY) { |io| FileUtils.rm_rf(dir) if io.flock(File::LOCK_EX | File::LOCK_NB) }
      else
        FileUtils.rm_rf(dir)
      end
    rescue SystemCallError
      next
    end
  end
end
