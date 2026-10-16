class SearchesController < ApplicationController
  def show
    @query = params[:q].to_s.squish
    @filters = Document.filter_params(params)
    @literal = Array(params[:literal]).compact_blank
    return @documents = [] if @query.blank? && @filters.empty?

    parsed = Search::QueryParser.new(@query, literal: @literal).call
    # Filters read from the query move into the filter bar, where they show
    # and can be changed. Filters already picked there win.
    understood, overridden = parsed.chips.partition { |chip| !chip.keys.intersect?(@filters.keys) }
    return redirect_to_filters(parsed, understood) if understood.any?

    @keywords = parsed.keywords
    filters = parsed.filters.stringify_keys.except(*overridden.flat_map(&:keys)).compact.merge(@filters)
    @documents = Search.new(query: @keywords, filters: filters).results(limit: 60)
  end

  private
    def redirect_to_filters(parsed, chips)
      flash[:read_as_filters] = chips.map { |chip| chip.to_h.stringify_keys }
      filters = parsed.filters.stringify_keys.slice(*chips.flat_map(&:keys)).compact
      redirect_to search_path(q: parsed.keywords.presence, literal: @literal.presence, **@filters.merge(filters).symbolize_keys)
    end
end
