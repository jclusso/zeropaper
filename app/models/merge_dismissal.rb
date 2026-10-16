class MergeDismissal < ApplicationRecord
  def self.dismiss!(first, second)
    low, high = [ first.id, second.id ].minmax
    find_or_create_by!(kind: first.class.name, first_id: low, second_id: high)
  end

  def self.pairs_for(model)
    where(kind: model.name).pluck(:first_id, :second_id).to_set
  end
end
