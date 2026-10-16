# Shared by correspondents, document types and tags.
module Taxonomy
  extend ActiveSupport::Concern

  included do
    normalizes :name, with: ->(name) { name.squish }

    validates :name, presence: true, length: { maximum: 120 }
    validate :name_unique_ignoring_case

    scope :alphabetically, -> { order(Arel.sql("lower(name)")) }

    # Names that may be shown to a hosted model. A name only attached to
    # private documents could say something about them, so it stays local.
    scope :shareable, -> {
      where(id: unscoped.left_joins(:documents).group(:id)
        .having("count(documents.id) = 0 OR bool_or(NOT documents.private)").select(:id))
    }
  end

  class_methods do
    def named(name)
      find_by("lower(name) = ?", name.to_s.squish.downcase) if name.present?
    end

    # `attributes` only apply when the record is new. The create runs in a
    # savepoint, so losing a race to another process leaves an outer
    # transaction usable for the lookup that follows.
    def find_or_create_named(name, **attributes)
      return if name.blank?

      named(name) || transaction(requires_new: true) { create!(name: name.to_s.squish.truncate(120, omission: ""), **attributes) }
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      named(name)
    end
  end

  private
    def name_unique_ignoring_case
      return if name.blank?

      duplicate = self.class.where("lower(name) = ?", name.downcase).where.not(id: id)
      errors.add(:name, "is already taken") if duplicate.exists?
    end
end
