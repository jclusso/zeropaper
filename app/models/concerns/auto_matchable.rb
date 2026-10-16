# Correspondents, document types and tags with auto_match on claim a
# document whose text mentions their name. Matching runs locally, so private
# documents get filed without any text leaving the machine. Anything more
# specific is a Rule.
module AutoMatchable
  extend ActiveSupport::Concern

  included do
    scope :auto_matching, -> { where(auto_match: true) }
  end

  class_methods do
    def mentioned_in(text)
      return [] if text.blank?

      auto_matching.select { |record| record.mentioned_in?(text) }
    end
  end

  def mentioned_in?(text)
    TextMatch.phrase?(text, name)
  end
end
