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
