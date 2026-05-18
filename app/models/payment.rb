class Payment < ApplicationRecord
  belongs_to :user
  belongs_to :subscription, optional: true

  before_create :generate_transaction_id

  validates :amount,   numericality: { greater_than: 0 }
  validates :provider, inclusion: { in: %w[stripe cinetpay mtn orange wave mvola orange_money airtel_money] }
  validates :status,   inclusion: { in: %w[pending success failed refunded] }

  scope :successful, -> { where(status: "success") }
  scope :pending,    -> { where(status: "pending") }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..) }

  def mark_success!(provider_ref:, response: nil)
    update!(
      status: "success",
      provider_ref: provider_ref,
      provider_response: response.to_json,
      paid_at: Time.current
    )
    subscription&.activate!
  end

  def mark_failed!(response: nil)
    update!(status: "failed", provider_response: response.to_json)
  end

  private

  def generate_transaction_id
    self.transaction_id ||= "DV-#{SecureRandom.alphanumeric(12).upcase}"
  end
end
