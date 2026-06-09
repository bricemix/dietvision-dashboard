class SavedPushTemplate < ApplicationRecord
  validates :name,  presence: true, length: { maximum: 60 }
  validates :title, presence: true, length: { maximum: 80 }
  validates :body,  presence: true, length: { maximum: 300 }
end
