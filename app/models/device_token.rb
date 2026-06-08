class DeviceToken < ApplicationRecord
  belongs_to :user

  PLATFORMS = %w[android ios].freeze

  validates :token, presence: true, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }
end
