# Correspondents, document types and tags drift into near-duplicates ("Car"
# and "Vehicle"). Merging moves everything onto one and deletes the other;
# similar_pairs suggests candidates, worked out locally.
module Mergeable
  extend ActiveSupport::Concern

  SPELLING_SIMILARITY = 0.6
  # A name contained in another only counts when it is specific enough on
  # its own: "Statement" in "Bank Statement", not "BMW" in "BMW X5 M".
  CONTAINED_MIN_LENGTH = 6
  # Short names score high against unrelated names too, so only near
  # synonyms clear this. Measured with the local embedding model.
  MEANING_SIMILARITY = 0.93
  MAX_NAMES_COMPARED = 300

  Pair = Struct.new(:keep, :merge, :reason, keyword_init: true)

  class_methods do
    # Likely duplicates, the one used by more documents kept by default.
    def similar_pairs(limit: 12)
      records = with_document_counts.limit(MAX_NAMES_COMPARED).to_a
      return [] if records.size < 2

      dismissed = MergeDismissal.pairs_for(self)
      found = {}
      spelling_pairs(records).each { |a, b| found[[ a.id, b.id ].minmax] ||= [ a, b, "Similar spelling" ] }
      meaning_pairs(records).each { |a, b| found[[ a.id, b.id ].minmax] ||= [ a, b, "Similar meaning" ] }

      found.reject { |ids, _| dismissed.include?(ids) }.values.first(limit).map do |a, b, reason|
        keep, merge = [ a, b ].sort_by { |record| [ -record.documents_count.to_i, record.name.length ] }
        Pair.new(keep: keep, merge: merge, reason: reason)
      end
    end

    def with_document_counts
      counts = reflect_on_association(:taggings) ? Tagging.group(:tag_id).select(:tag_id, "count(*) AS n") : Document.group(foreign_key_for_documents).select(foreign_key_for_documents, "count(*) AS n")
      key = reflect_on_association(:taggings) ? "tag_id" : foreign_key_for_documents
      joins("LEFT JOIN (#{counts.to_sql}) document_counts ON document_counts.#{key} = #{table_name}.id")
        .select("#{table_name}.*", "coalesce(document_counts.n, 0) AS documents_count")
        .order(Arel.sql("coalesce(document_counts.n, 0) desc"))
    end

    def foreign_key_for_documents
      "#{model_name.singular}_id"
    end

    private
      def spelling_pairs(records)
        records.combination(2).select do |a, b|
          x, y = a.name.downcase, b.name.downcase
          short, long = [ x, y ].sort_by(&:length)
          contains = short.length >= CONTAINED_MIN_LENGTH && short != long && long.match?(/(?<![[:alnum:]])#{Regexp.escape(short)}(?![[:alnum:]])/)
          plural = x.split.map(&:singularize) == y.split.map(&:singularize)
          plural || contains || trigram_similarity(x, y) >= SPELLING_SIMILARITY
        end
      end

      def meaning_pairs(records)
        vectors = Rails.cache.fetch([ "taxonomy-name-vectors", name, Digest::SHA256.hexdigest(records.map(&:name).sort.join("\n")) ], expires_in: 1.day) do
          Embedder.embed_documents(records.map(&:name))
        end
        records.each_with_index.to_a.combination(2).filter_map do |(a, i), (b, j)|
          [ a, b ] if vectors[i].zip(vectors[j]).sum { |x, y| x * y } >= MEANING_SIMILARITY
        end
      rescue StandardError => error
        Rails.logger.warn("[merge] meaning comparison unavailable: #{error.message}")
        []
      end

      def trigram_similarity(x, y)
        connection.select_value(sanitize_sql_array([ "SELECT similarity(?, ?)", x, y ])).to_f
      end
  end

  # Moves documents and rules onto target, then deletes this record.
  def merge_into!(target)
    raise ArgumentError, "Choose a different #{model_name.human.downcase} to merge into" if target.nil? || target == self || target.class != self.class

    transaction do
      affected = affected_document_ids
      move_to(target)
      MergeDismissal.where(kind: self.class.name).where("first_id = :id OR second_id = :id", id: id).delete_all
      destroy!
      Document.where(id: affected).find_each(&:refresh_search_vector)
    end
    target
  end
end
