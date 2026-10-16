module Document::Filterable
  extend ActiveSupport::Concern

  FILTER_KEYS = %i[correspondent_id document_type_ids tag_ids date_from date_to privacy status].freeze
  LIST_KEYS = %i[document_type_ids tag_ids].freeze

  class_methods do
    # The filters in request params, without blanks. Types and tags are lists.
    def filter_params(params)
      params.permit(*(FILTER_KEYS - LIST_KEYS), **LIST_KEYS.index_with { [] }).to_h
        .transform_values { |value| value.is_a?(Array) ? value.compact_blank : value }.compact_blank
    end

    # Any of the chosen types; every one of the chosen tags.
    def filter_by(params)
      params = params.to_h.symbolize_keys.slice(*FILTER_KEYS).compact_blank
      scope = all
      scope = scope.where(correspondent_id: params[:correspondent_id]) if params[:correspondent_id]
      scope = scope.where(document_type_id: Array(params[:document_type_ids])) if params[:document_type_ids]
      Array(params[:tag_ids]).each { |tag_id| scope = scope.where(id: Tagging.where(tag_id: tag_id).select(:document_id)) }
      scope = scope.where(document_date: parse_date(params[:date_from])..) if parse_date(params[:date_from])
      scope = scope.where(document_date: ..parse_date(params[:date_to])) if parse_date(params[:date_to])
      scope = scope.where(private: true) if params[:privacy] == "private"
      scope = scope.where(private: false) if params[:privacy] == "shareable"
      scope = scope.where(status: params[:status]) if params[:status].in?(Document::STATUSES)
      scope
    end

    private
      def parse_date(value)
        value.is_a?(Date) ? value : Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
