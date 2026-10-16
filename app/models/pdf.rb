require "open3"

# Thin wrappers around poppler and qpdf, which ship in the app image.
module Pdf
  class CommandFailed < StandardError; end

  extend self

  def page_count(path)
    output = run("pdfinfo", path)
    output[/^Pages:\s+(\d+)/, 1].to_i
  end

  # Text per page from the PDF's own text layer.
  def text_pages(path)
    run("pdftotext", "-layout", "-enc", "UTF-8", path, "-").split("\f", -1).tap do |pages|
      pages.pop if pages.last.blank?
    end
  end

  # Width and height in points of each page, in page order.
  def page_sizes(path)
    run("pdfinfo", "-f", "1", "-l", page_count(path).to_s, path)
      .scan(/^Page\s+\d+\s+size:\s+([\d.]+) x ([\d.]+) pts/)
      .map { |width, height| [ width.to_f, height.to_f ] }
  end

  # The share of each page (1-based) covered by its largest image, from 0 to 1.
  # A scan is one image filling the page.
  def image_coverage(path)
    sizes = page_sizes(path)
    coverage = Hash.new(0.0)
    run("pdfimages", "-list", path).lines.drop(2).each do |line|
      fields = line.split
      page, width, height, x_ppi, y_ppi = fields[0].to_i, fields[3].to_f, fields[4].to_f, fields[12].to_f, fields[13].to_f
      next unless sizes[page - 1] && x_ppi.positive? && y_ppi.positive?

      page_width, page_height = sizes[page - 1]
      share = (width / x_ppi * 72) * (height / y_ppi * 72) / (page_width * page_height)
      coverage[page] = [ coverage[page], share.clamp(0, 1) ].max
    end
    coverage
  end

  # Renders one page (1-based) and returns the encoded image bytes.
  def render_page(path, page, edge:, format: :jpeg)
    Dir.mktmpdir do |dir|
      prefix = File.join(dir, "page")
      flag = { jpeg: "-jpeg", png: "-png" }.fetch(format)
      run("pdftoppm", flag, "-f", page.to_s, "-l", page.to_s, "-scale-to", edge.to_s, "-singlefile", path, prefix)
      File.binread(Dir.glob("#{prefix}.*").first)
    end
  end

  # Renders every page in grayscale as PGM files and yields their paths in
  # page order.
  def render_gray_pages(path, edge:)
    Dir.mktmpdir do |dir|
      run("pdftoppm", "-gray", "-scale-to", edge.to_s, path, File.join(dir, "page"))
      yield Dir.glob(File.join(dir, "page-*.pgm")).sort_by { |file| file[/-(\d+)\.pgm\z/, 1].to_i }
    end
  end

  # Writes a copy of the PDF without the given pages (1-based).
  def without_pages(path, pages, output)
    keep = (1..page_count(path)).to_a - pages
    only_pages(path, keep, output)
  end

  # Writes a copy with pages turned clockwise, given { page => degrees }.
  def rotate_pages(path, rotations, output)
    turns = rotations.group_by { |_page, degrees| degrees }.map do |degrees, pages|
      "--rotate=+#{degrees}:#{pages.map(&:first).sort.join(",")}"
    end
    run("qpdf", path, *turns, "--", output)
  end

  def only_pages(path, pages, output)
    raise ArgumentError, "no pages to keep" if pages.empty?

    run("qpdf", "--empty", "--pages", path, pages.join(","), "--", output)
  end

  # Long enough for a big scan, short enough that a hung tool cannot hold a
  # worker forever.
  COMMAND_TIMEOUT = 10.minutes

  def run(*command, timeout: COMMAND_TIMEOUT)
    stdout, stderr, status = capture(*command, timeout: timeout)
    # qpdf exits 3 for warnings that still produce a valid file.
    return stdout if status.success? || (command.first == "qpdf" && status.exitstatus == 3)

    raise CommandFailed, "#{command.first} failed: #{stderr.presence || stdout}".truncate(500)
  end

  # Open3.capture3 with a time limit. The command runs in its own process
  # group so tools that start helpers (ocrmypdf starts tesseract) are stopped
  # together.
  def capture(*command, timeout:)
    Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, wait|
      stdin.close
      output = Thread.new { stdout.read }
      errors = Thread.new { stderr.read }

      unless wait.join(timeout)
        stop_group(wait.pid)
        raise CommandFailed, "#{command.first} did not finish within #{timeout.inspect} and was stopped"
      end

      [ output.value, errors.value, wait.value ]
    end
  end

  def stop_group(pid)
    Process.kill("-TERM", pid)
    sleep 2
    Process.kill("-KILL", pid)
  rescue Errno::ESRCH
    nil
  end
end
