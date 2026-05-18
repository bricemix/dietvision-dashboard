class AdminLog < ApplicationRecord
  belongs_to :admin_user, optional: true

  scope :recent, -> { order(created_at: :desc) }

  def details
    JSON.parse(details_json || "{}") rescue {}
  end

  def self.log(admin:, action:, resource: nil, details: {}, ip: nil)
    create!(
      admin_user_id: admin&.id,
      action:        action.to_s,
      resource_type: resource&.class&.name,
      resource_id:   resource&.id,
      details_json:  details.to_json,
      ip_address:    ip.to_s
    )
  rescue => e
    Rails.logger.warn("AdminLog.log failed: #{e.message}")
  end
end
