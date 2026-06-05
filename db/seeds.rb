# ─── Utilisateurs test ────────────────────────────────────────────
[
  { name: "Test User",    email: "test@dietvision.app",  password: "Test1234!", phone: "+225 07 00 00 01", country: "CI", plan: "free" },
  { name: "Marie Konan",  email: "marie@dietvision.app", password: "Test1234!", phone: "+225 05 00 00 02", country: "CI", plan: "premium",
    subscription_expires_at: 1.year.from_now }
].each do |attrs|
  u = User.find_or_initialize_by(email: attrs[:email])
  u.assign_attributes(attrs)
  u.save!
  puts "✓ User : #{u.email} / #{attrs[:password]}  [#{u.plan}]"
end

# ─── Admin par défaut ─────────────────────────────────────────────
AdminUser.find_or_create_by!(email: "admin@dietvision.app") do |u|
  u.name     = "Super Admin"
  u.password = "DietVision2026!"
  u.role     = "superadmin"
end
puts "✓ Admin créé : admin@dietvision.app / DietVision2026!"

# ─── Configuration par défaut ─────────────────────────────────────
defaults = {
  "openrouter_api_key"       => "",
  "openrouter_default_model" => "google/gemini-2.0-flash-001",
  "openrouter_vision_model"  => "google/gemini-2.0-flash-001",
  "free_plan_daily_limit"    => "5",
  "premium_plan_daily_limit" => "100",
  "cinetpay_api_key"         => "",
  "cinetpay_site_id"         => "",
  "app_name"                 => "DietVision",
  "support_email"            => "support@dietvision.app"
}

defaults.each do |key, value|
  AppConfig.find_or_create_by!(key: key) do |c|
    c.value = value
  end
end
puts "✓ #{defaults.size} clés de configuration initialisées"

# ─── Configuration essai ─────────────────────────────────────────
trial_defaults = {
  "trial_enabled"        => "true",
  "trial_days"           => "7",
  "trial_max_per_device" => "1",
  "trial_expiry_message" => "Votre essai expire dans 2 jours. Passez à Premium pour continuer à utiliser DietVision sans limite.",
  "trial_features"       => { scan_ai: true, chatbot: true, graphs: true, pdf_export: false }.to_json
}
trial_defaults.each { |k, v| AppConfig.find_or_create_by!(key: k) { |c| c.value = v } }
puts "✓ Configuration essai initialisée"

# ─── Plans tarifaires de démo ─────────────────────────────────────
plans_data = [
  {
    name: "Starter", slug: "starter", position: 1, status: "active",
    billing_frequency: "monthly", price_ariary: 3_900,
    badge: nil,
    features: [
      "20 analyses photo par jour",
      "Coach IA illimité",
      "Suivi calories & macros",
      "Historique 30 jours"
    ],
    operators: %w[mvola orange_money airtel_money]
  },
  {
    name: "Pro", slug: "pro", position: 2, status: "active",
    billing_frequency: "monthly", price_ariary: 7_900,
    badge: "popular",
    features: [
      "Analyses photo illimitées",
      "Coach IA illimité",
      "Suivi calories & macros",
      "Historique complet",
      "Export PDF mensuel",
      "Objectifs personnalisés"
    ],
    operators: %w[mvola orange_money airtel_money]
  },
  {
    name: "Premium Annuel", slug: "premium-annual", position: 3, status: "active",
    billing_frequency: "yearly", price_ariary: 59_000,
    badge: "recommended",
    features: [
      "Tout le plan Pro",
      "2 mois offerts",
      "Support prioritaire",
      "Accès aux nouvelles fonctionnalités en avant-première"
    ],
    operators: %w[mvola orange_money airtel_money]
  }
]

plans_data.each do |attrs|
  plan = Plan.find_or_initialize_by(slug: attrs[:slug])
  plan.assign_attributes(attrs.except(:features, :operators))
  plan.features  = attrs[:features]
  plan.operators = attrs[:operators]
  plan.save!
  puts "✓ Plan : #{plan.name} (#{plan.price_formatted}/#{plan.frequency_label.downcase})"
end
