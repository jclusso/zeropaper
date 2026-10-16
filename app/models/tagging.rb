class Tagging < ApplicationRecord
  belongs_to :document, touch: true
  belongs_to :tag
end
