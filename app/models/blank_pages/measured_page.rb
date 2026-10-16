module BlankPages
  class MeasuredPage
    # A back showing its front through the paper matches the mirrored front
    # at least this well...
    MIRRORED_MATCH = 0.45
    # ...and clearly better than the front as printed. The margin tells
    # bleed-through from two pages of the same form, which match each other
    # whichever way round they are laid.
    MIRROR_MARGIN = 0.2
    # Bleed-through is the front's print seen through paper, so it carries a
    # fraction of the front's ink. A real page that happens to line up with
    # its mirrored neighbour is as dark as that neighbour.
    BLEED_INK_SHARE = 0.35
    BLEED_SOLID_SHARE = 0.25

    attr_reader :ink, :grid

    def initialize(image)
      @ink = InkProfile.measure(image)
      @grid = DarknessGrid.new(image)
    end

    # Whether this page carries nothing but the front seen through the
    # sheet: a mirror image of it, and a faint one.
    def shows_through?(front)
      return false if front.nil? || front.ink.ink.zero? || front.ink.solid.zero?
      return false if ink.ink > BLEED_INK_SHARE * front.ink.ink || ink.solid > BLEED_SOLID_SHARE * front.ink.solid

      mirrored = grid.match(front.grid, mirrored: true)
      mirrored >= MIRRORED_MATCH && mirrored - grid.match(front.grid, mirrored: false) >= MIRROR_MARGIN
    end
  end
end
