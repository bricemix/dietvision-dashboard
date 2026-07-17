class PromoCode < ApplicationRecord
  DISCOUNT_TYPES = %w[percent fixed].freeze
  STATUSES       = %w[active expired disabled].freeze

  has_many :promo_code_redemptions, dependent: :destroy
  has_many :redeeming_users, through: :promo_code_redemptions, source: :user

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

  def notification_emails
    JSON.parse(notification_emails_json || "[]") rescue []
  end

  # Accepte un tableau OU une chaîne (emails séparés par virgule/saut de ligne),
  # pour supporter à la fois un formulaire multi-champs et un simple textarea.
  def notification_emails=(value)
    list = value.is_a?(String) ? value.split(/[,\n]/) : Array(value)
    self.notification_emails_json = list.map(&:to_s).map(&:strip).reject(&:blank?)
                                         .select { |e| e.match?(URI::MailTo::EMAIL_REGEXP) }
                                         .uniq.to_json
  end

  # ── Business logic ──────────────────────────────────────────

  def valid_now?
    status == "active" &&
      (starts_at.nil? || starts_at <= Time.current) &&
      (expires_at.nil? || expires_at >= Time.current) &&
      (max_uses_total.nil? || uses_count < max_uses_total)
  end

  # Statut réel tenant compte de la date d'expiration, sans dépendre d'un job
  # planifié pour mettre à jour la colonne `status` en base (celle-ci ne change
  # que sur désactivation manuelle ou atteinte du quota max_uses_total).
  def effective_status
    return "expired" if status == "active" && expires_at.present? && expires_at < Time.current
    status
  end

  def expired_by_date?
    expires_at.present? && expires_at < Time.current
  end

  # BUG-14 FIXÉ : with_lock pour éviter la race condition sur uses_count
  # Sans verrou, deux requêtes simultanées pouvaient dépasser max_uses_total.
  def increment_usage!
    with_lock do
      increment!(:uses_count)
      update_column(:status, "expired") if max_uses_total && uses_count >= max_uses_total
    end
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
