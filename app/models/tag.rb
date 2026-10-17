class Tag < ApplicationRecord
  include AutoMatchable, Taxonomy, Mergeable

  COLORS = %w[slate red orange amber lime emerald teal sky indigo violet pink].freeze

  has_many :taggings, dependent: :delete_all
  has_many :documents, through: :taggings

  validates :color, inclusion: { in: COLORS }

  before_validation -> { self.color = COLORS[name.to_s.sum % COLORS.size] }, on: :create, unless: :color_changed?
  after_destroy :remove_from_rules

  private
    # rules.tag_ids is a plain array with no foreign key, so a deleted tag
    # leaves it here. A rule that only added this tag has nothing left to
    # do, so it is turned off rather than matching documents for nothing.
    def remove_from_rules
      rules = Rule.where("? = ANY(tag_ids)", id)
      rule_ids = rules.ids
      rules.update_all([ "tag_ids = array_remove(tag_ids, ?::bigint)", id ])
      Rule.where(id: rule_ids).without_action.update_all(enabled: false, updated_at: Time.current)
    end

    def affected_document_ids
      taggings.pluck(:document_id)
    end

    def move_to(target)
      already = target.taggings.select(:document_id)
      taggings.where.not(document_id: already).update_all(tag_id: target.id)
      taggings.delete_all
      self.class.connection.execute(self.class.sanitize_sql_array([ <<~SQL, id, target.id, id ]))
        UPDATE rules SET tag_ids = ARRAY(SELECT DISTINCT unnest(array_replace(tag_ids, ?::bigint, ?::bigint)))
        WHERE ? = ANY(tag_ids)
      SQL
    end
end
