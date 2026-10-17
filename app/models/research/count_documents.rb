# Counts documents, optionally filtered and grouped. Only non-private
# documents are counted, so the model's numbers never reveal private ones,
# and the counted documents are registered with the research, so each later
# request checks them again and the answer records them.
class Research::CountDocuments < Research::Tool
  GROUPS = %w[none correspondent document_type tag year month].freeze

  description "Counts documents in the archive, optionally filtered, grouped by correspondent, document_type, tag, year or month."
  parameter :group_by, description: "One of: #{GROUPS.join(", ")}", required: false
  parameter :date_from, description: "YYYY-MM-DD", required: false
  parameter :date_to, description: "YYYY-MM-DD", required: false
  parameter :correspondent, description: "Exact correspondent name", required: false
  parameter :document_type, description: "Exact document type name", required: false
  parameter :tag, description: "Exact tag name", required: false

  def execute(group_by: "none", date_from: nil, date_to: nil, correspondent: nil, document_type: nil, tag: nil)
    scope = Document.ready.shareable.filter_by(filters(date_from:, date_to:, correspondent:, document_type:, tag:))
    research.shareable(scope.select(:id, :private).to_a)

    counts =
      case group_by
      when "correspondent" then scope.left_joins(:correspondent).group("correspondents.name").count
      when "document_type" then scope.left_joins(:document_type).group("document_types.name").count
      when "tag" then scope.joins(:tags).group("tags.name").count
      when "year" then scope.group(Arel.sql("extract(year from documents.document_date)::int")).count
      when "month" then scope.group(Arel.sql("to_char(documents.document_date, 'YYYY-MM')")).count
      else { "all" => scope.count }
      end

    { counts: counts.transform_keys { |key| key.nil? ? "(none)" : key.to_s }.sort_by { |_, count| -count }.to_h }
  end
end
