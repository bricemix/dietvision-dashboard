class Plan < ApplicationRecord
  FREQUENCIES = %w[monthly quarterly semi_annual yearly].freeze
  STATUSES    = %w[active inactive draft].freeze
  OPERATORS   = %w[mvola orange_money airtel_money].freeze
  BADGES      = %w[popular recommended].freeze

  EMAIL_FREQUENCIES = %w[never daily weekly monthly].freeze
  EMAIL_FREQUENCY_LABELS = {
    'never'   => 'Jamais',
    'daily'   => 'Quotidien',
    'weekly'  => 'Hebdomadaire',
    'monthly' => 'Mensuel'
  }.freeze

  OPERATOR_LABELS = {
    "mvola"        => "MVola",
    "orange_money" => "Orange Money",
    "airtel_money" => "Airtel Money"
  }.freeze

  FREQUENCY_LABELS = {
    "monthly"    => "Mensuel",
    "quarterly"  => "Trimestriel",
    "semi_annual" => "Semestriel",
    "yearly"     => "Annuel"
  }.freeze

  validates :name, :billing_frequency, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false }
  validates :price_ariary, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :billing_frequency, inclusion: { in: FREQUENCIES }

  before_validation { self.slug = name.to_s.downcase.strip.gsub(/\s+/, '-').gsub(/[^a-z0-9\-]/, '') if slug.blank? }

  scope :active,    -> { where(status: "active").order(:position, :id) }
  scope :published, -> { where(status: %w[active inactive]).order(:position, :id) }

  # ── JSON accessors ──────────────────────────────────────────

  def features
    JSON.parse(features_json || "[]") rescue []
  end

  def features=(arr)
    self.features_json = Array(arr).reject(&:blank?).to_json
  end

  def features_excluded
    JSON.parse(features_excluded_json || "[]") rescue []
  end

  def features_excluded=(arr)
    self.features_excluded_json = Array(arr).reject(&:blank?).to_json
  end

  # ── Multilingual translations ───────────────────────────────
  # Structure: { "fr" => { "name" => "...", "description" => "...",
  #              "features" => [...], "features_excluded" => [...], "cta_label" => "..." },
  #              "en" => { ... }, "de" => { ... }, "es" => { ... } }

  LOCALES = %w[fr en de es].freeze

  def translations
    JSON.parse(translations_json || "{}") rescue {}
  end

  def translations=(hash)
    self.translations_json = hash.to_json
  end

  # Returns translated fields for a given locale, falling back to default (fr) then to base columns.
  def translate(locale = "fr")
    t = translations[locale.to_s] || translations["fr"] || {}
    {
      "name"              => t["name"].presence || name,
      "description"       => t["description"].presence || description.to_s,
      "features"          => t["features"].presence || features,
      "features_excluded" => t["features_excluded"].presence || features_excluded,
      "cta_label"         => t["cta_label"].presence || (respond_to?(:cta_label) ? self[:cta_label] : nil) || "Essayer 7 jours gratuits"
    }
  end

  def operators
    JSON.parse(operators_json || "[]") rescue []
  end

  def operators=(arr)
    self.operators_json = Array(arr).reject(&:blank?).to_json
  end

  # Prices per currency : { "USD" => 499, "EUR" => 399, "XOF" => 3025, … }
  # Convention:
  #   - "Small" currencies (USD, EUR, GBP, CHF, CAD…) → value in cents  (399 = €3.99)
  #   - "Large" currencies (XOF, NGN, MGA, KES…)      → value in whole units (3025 = 3 025 F CFA)
  # Format alternatif : "3.99" est accepté et converti en centimes (399)
  def prices
    JSON.parse(prices_json.presence || "{}") rescue {}
  end

  def prices=(hash)
    normalized = hash.transform_values do |v|
      v.is_a?(String) && v.include?(".") ? (v.to_f * 100).round : v.to_i
    end
    self.prices_json = normalized.to_json
  end

  # Returns the native price for a given ISO currency code (in cents).
  # Falls back to EUR, then to price_usd_cents.
  def price_for(currency_code = "EUR")
    p = prices
    code = currency_code.to_s.upcase
    if p[code].to_i > 0
      p[code].to_i
    elsif code != "EUR" && p["EUR"].to_i > 0
      p["EUR"].to_i
    else
      price_usd_cents.to_i
    end
  end

  # Retourne le prix formaté pour affichage (ex: "3.99 €" ou "3 025 XOF")
  def price_formatted_for(currency_code = "EUR")
    cents = price_for(currency_code)
    case currency_code.to_s.upcase
    when "EUR", "USD", "GBP", "CHF", "CAD"
      "#{"%.2f" % (cents / 100.0)} #{currency_code}"
    else
      parts = cents.to_s.chars.reverse.each_slice(3).map(&:join).join(" ").reverse
      "#{parts} #{currency_code}"
    end
  end

  # Retourne le prix par défaut en EUR (pour compatibilité Stripe)
  def price_eur_cents
    p = prices
    p["EUR"].to_i > 0 ? p["EUR"].to_i : price_usd_cents.to_i
  end

  # ── Stripe helpers ──────────────────────────────────────────

  # Durée d'abonnement en secondes (pour activer le compte après paiement)
  def duration
    case billing_frequency
    when "monthly"    then 1.month
    when "quarterly"  then 3.months
    when "semi_annual" then 6.months
    when "yearly"     then 1.year
    else 1.month
    end
  end

  # Prix en USD (centimes → dollars formatés)
  # Par défaut, utilise le prix EUR converti
  def price_usd_formatted
    return "—" if price_usd_cents.to_i == 0 && price_eur_cents == 0
    cents = price_eur_cents > 0 ? price_eur_cents : price_usd_cents.to_i
    "€#{"%.2f" % (cents / 100.0)}"
  end

  def stripe_configured?
    stripe_price_id.present?
  end

  # ── Display helpers ──────────────────────────────────────────

  # Prix par défaut en euros (affichage principal)
  def price_formatted
    price_formatted_for("EUR")
  end

  def frequency_label
    FREQUENCY_LABELS[billing_frequency] || billing_frequency
  end

  def operator_labels
    operators.map { |o| OPERATOR_LABELS[o] || o }
  end

  def active?   = status == "active"
  def draft?    = status == "draft"
  def inactive? = status == "inactive"
end
