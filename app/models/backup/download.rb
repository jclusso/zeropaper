# A response body that streams a backup from a handle Backup.open_file
# checked, rather than from its path, which could be swapped for a link
# before the server opened it.
class Backup::Download
  CHUNK = 64.kilobytes

  def initialize(io)
    @io = io
  end

  def each
    while (chunk = @io.read(CHUNK))
      yield chunk
    end
  ensure
    close
  end

  def close
    @io.close unless @io.closed?
  end
end
