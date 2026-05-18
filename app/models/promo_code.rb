class PromoCode < ApplicationRecord
  DISCOUNT_TYPES = %w[percent fixed].freeze
  STATUSES       = %w[active expired disabled].freeze

  validates :code,           presence: true, uniqueness: { case_sensitive: false }
  validates :discount_type,  inclusion: { in: DISCOUNT_TYPES }
  validates :discount_value, numericality: { greater_than: 0 }
  validates :status,         inclusion: { in: STATUSES }

  before_save { self.code = code.upcase.strip }

  scope :active,  -> { where(status: "active") }
  scope :current, -> {
    active
      .where("starts_at IS NULL OR starts_at <= ?", Time.current)
      .where("expires_at IS NULL OR expires_at >= ?", Time.current)
  }

  # ── JSON accessors ──────────────────────────────────────────

  def applicable_plans
    JSON.parse(applicable_plans_json || "[]") rescue []
  end

  def applicable_plans=(arr)
    self.applicable_plans_json = Array(arr).reject(&:blank?).to_json
  end

  # ── Business logic ──────────────────────────────────────────

  def valid_now?
    status == "active" &&
      (starts_at.nil? || starts_at <= Time.current) &&
      (expires_at.nil? || expires_at >= Time.current) &&
      (max_uses_total.nil? || uses_count < max_uses_total)
  end

  def increment_usage!
    increment!(:uses_count)
    update_column(:status, "expired") if max_uses_total && uses_count >= max_uses_total
  end

  # ── Display ──────────────────────────────────────────────────

  def discount_label
    discount_type == "percent" ? "#{discount_value.to_i}%" : "#{discount_value.to_i} Ar"
  end

  def status_color
    case status
    when "active"   then "lime"
    when "expired"  then "text-yellow-400"
    when "disabled" then "text-red-400"
    end
  end

  def self.generate_bulk!(count:, prefix:, discount_type:, discount_value:, expires_at: nil, max_uses_total: 1)
    generated = []
    attempts  = 0
    while generated.size < count && attempts < count * 5
      attempts += 1
      code = "#{prefix}#{SecureRandom.alphanumeric(6).upcase}"
      next if exists?(code: code)
      begin
        pc = create!(
          code: code, discount_type: discount_type, discount_value: discount_value,
          expires_at: expires_at, status: "active",
          max_uses_total: max_uses_total, max_uses_per_user: 1
        )
        generated << pc
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end
    generated
  end
end
