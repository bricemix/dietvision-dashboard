class ApiUsage < ApplicationRecord
  belongs_to :user

  validates :endpoint, inclusion: { in: %w[analyze_food coach_chat dish_recommendation] }

  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..) }
  scope :today,      -> { where(created_at: Time.current.beginning_of_day..) }

  def self.total_cost
    sum(:cost_usd)
  end

  def self.by_day(days = 30)
    where(created_at: days.days.ago..)
      .group_by_day(:created_at)
      .count
  end
end
