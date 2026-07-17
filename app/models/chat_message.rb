class ChatMessage < ApplicationRecord
  belongs_to :user
  validates :role,    inclusion: { in: %w[user assistant] }
  validates :content, presence: true
  scope :ordered, -> { order(:created_at) }
end
