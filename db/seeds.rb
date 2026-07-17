# ─── Utilisateurs test ────────────────────────────────────────────
[
  { name: "Test User",    email: "test@dietvision.app",  password: "Test1234!", phone: "+225 07 00 00 01", country: "CI", plan: "free" },
  { name: "Marie Konan",  email: "marie@dietvision.app", password: "Test1234!", phone: "+225 05 00 00 02", country: "CI", plan: "premium",
    subscription_expires_at: 1.year.from_now },
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
  "free_plan_daily_limit"    => "3",
  "pro_plan_daily_limit"     => "30",
  "premium_plan_daily_limit" => "75",
  "vip_plan_daily_limit"     => "999",
  "trial_plan_daily_limit"   => "20",
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

# ─── Plans tarifaires ────────────────────────────────────────────
# Structure : 4 plans × 2 fréquences (mensuel + annuel -33%)
# Prix en centimes : EUR 499 = 4.99 €
plans_data = [
  # ── Starter (gratuit) ────────────────────────────────────────────
  {
    name: "Starter", slug: "starter", position: 1, status: "active",
    billing_frequency: "monthly", price_ariary: 0, badge: nil,
    description: "Découvrez DietVision gratuitement. 7 jours d'essai inclus.",
    prices: { "EUR" => 0, "USD" => 0 },
    features: [
      "3 scans photo IA / jour",
      "3 questions coach IA / jour",
      "Dashboard calories & macros",
      "Missions quotidiennes",
      "Mesures corporelles & graphiques",
      "Historique 7 jours",
      "Essai 7 jours inclus"
    ],
    features_excluded: [
      "Plats recommandés par l'IA",
      "Planning nutritionnel",
      "Sync multi-appareils",
      "Rapport email"
    ],
    translations: {
      "en" => {
        "name" => "Starter", "description" => "Discover DietVision for free. 7-day trial included.",
        "cta_label" => "Get started free",
        "features" => [
          "3 AI photo scans / day", "3 AI coach questions / day",
          "Calories & macros dashboard", "Daily missions",
          "Body measurements & charts", "7-day history", "7-day trial included"
        ],
        "features_excluded" => ["AI dish recommendations", "Nutritional planning", "Multi-device sync", "Email report"]
      },
      "fr" => {
        "name" => "Starter", "description" => "Découvrez DietVision gratuitement. 7 jours d'essai inclus.",
        "cta_label" => "Commencer gratuitement",
        "features" => [
          "3 scans photo IA / jour", "3 questions coach IA / jour",
          "Dashboard calories & macros", "Missions quotidiennes",
          "Mesures corporelles & graphiques", "Historique 7 jours", "Essai 7 jours inclus"
        ],
        "features_excluded" => ["Plats recommandés par l'IA", "Planning nutritionnel", "Sync multi-appareils", "Rapport email"]
      }
    }
  },

  # ── Pro mensuel ───────────────────────────────────────────────────
  {
    name: "Pro", slug: "pro", position: 2, status: "active",
    billing_frequency: "monthly", price_ariary: 2_500,
    badge: "popular",
    description: "L'essentiel pour progresser vraiment.",
    prices: { "EUR" => 499, "USD" => 499 },
    features: [
      "30 scans photo IA / jour",
      "30 questions coach IA / jour",
      "Historique illimité",
      "Plats recommandés par l'IA",
      "10 régimes & filtres",
      "Sync multi-appareils",
      "Rapport hebdomadaire email",
      "Rappels personnalisés"
    ],
    features_excluded: ["Planning nutritionnel hebdomadaire", "Support prioritaire"],
    translations: {
      "en" => {
        "name" => "Pro", "description" => "Everything you need to actually progress.",
        "cta_label" => "Start Pro",
        "features" => [
          "30 AI photo scans / day", "30 AI coach questions / day",
          "Unlimited history", "AI dish recommendations",
          "10 diets & filters", "Multi-device sync",
          "Weekly email report", "Personalized reminders"
        ],
        "features_excluded" => ["Weekly nutritional planning", "Priority support"]
      },
      "fr" => {
        "name" => "Pro", "description" => "L'essentiel pour progresser vraiment.",
        "cta_label" => "Passer à Pro",
        "features" => [
          "30 scans photo IA / jour", "30 questions coach IA / jour",
          "Historique illimité", "Plats recommandés par l'IA",
          "10 régimes & filtres", "Sync multi-appareils",
          "Rapport hebdomadaire email", "Rappels personnalisés"
        ],
        "features_excluded" => ["Planning nutritionnel hebdomadaire", "Support prioritaire"]
      }
    }
  },

  # ── Pro annuel (-33%) ─────────────────────────────────────────────
  {
    name: "Pro", slug: "pro-yearly", position: 2, status: "active",
    billing_frequency: "yearly", price_ariary: 20_000,
    badge: "popular", savings_percent: 33,
    description: "L'essentiel pour progresser vraiment.",
    prices: { "EUR" => 3999, "USD" => 3999 },
    features: [
      "30 scans photo IA / jour",
      "30 questions coach IA / jour",
      "Historique illimité",
      "Plats recommandés par l'IA",
      "10 régimes & filtres",
      "Sync multi-appareils",
      "Rapport hebdomadaire email",
      "Rappels personnalisés"
    ],
    features_excluded: ["Planning nutritionnel hebdomadaire", "Support prioritaire"],
    translations: {
      "en" => {
        "name" => "Pro", "description" => "Everything you need to actually progress.",
        "cta_label" => "Start Pro — Save 33%",
        "features" => [
          "30 AI photo scans / day", "30 AI coach questions / day",
          "Unlimited history", "AI dish recommendations",
          "10 diets & filters", "Multi-device sync",
          "Weekly email report", "Personalized reminders"
        ]
      },
      "fr" => {
        "name" => "Pro", "description" => "L'essentiel pour progresser vraiment.",
        "cta_label" => "Passer à Pro — -33%"
      }
    }
  },

  # ── Premium mensuel ───────────────────────────────────────────────
  {
    name: "Premium", slug: "premium", position: 3, status: "active",
    billing_frequency: "monthly", price_ariary: 5_000,
    badge: "recommended",
    description: "L'expérience complète, du scan au planning.",
    prices: { "EUR" => 999, "USD" => 999 },
    features: [
      "75 scans photo IA / jour",
      "75 questions coach IA / jour",
      "Tout de Pro inclus",
      "Planning nutritionnel hebdomadaire",
      "Rapport IA personnalisé",
      "Support prioritaire"
    ],
    translations: {
      "en" => {
        "name" => "Premium", "description" => "The complete experience, from scan to planning.",
        "cta_label" => "Start Premium",
        "features" => [
          "75 AI photo scans / day", "75 AI coach questions / day",
          "Everything in Pro", "Weekly nutritional planning",
          "Personalized AI report", "Priority support"
        ]
      },
      "fr" => {
        "name" => "Premium", "description" => "L'expérience complète, du scan au planning.",
        "cta_label" => "Passer à Premium",
        "features" => [
          "75 scans photo IA / jour", "75 questions coach IA / jour",
          "Tout de Pro inclus", "Planning nutritionnel hebdomadaire",
          "Rapport IA personnalisé", "Support prioritaire"
        ]
      }
    }
  },

  # ── Premium annuel (-33%) ─────────────────────────────────────────
  {
    name: "Premium", slug: "premium-yearly", position: 3, status: "active",
    billing_frequency: "yearly", price_ariary: 40_000,
    badge: "recommended", savings_percent: 33,
    description: "L'expérience complète, du scan au planning.",
    prices: { "EUR" => 7999, "USD" => 7999 },
    features: [
      "75 scans photo IA / jour",
      "75 questions coach IA / jour",
      "Tout de Pro inclus",
      "Planning nutritionnel hebdomadaire",
      "Rapport IA personnalisé",
      "Support prioritaire"
    ],
    translations: {
      "en" => {
        "name" => "Premium", "description" => "The complete experience, from scan to planning.",
        "cta_label" => "Start Premium — Save 33%"
      },
      "fr" => {
        "name" => "Premium", "description" => "L'expérience complète, du scan au planning.",
        "cta_label" => "Passer à Premium — -33%"
      }
    }
  },

  # ── VIP mensuel ───────────────────────────────────────────────────
  {
    name: "VIP", slug: "vip", position: 4, status: "active",
    billing_frequency: "monthly", price_ariary: 10_000,
    badge: nil,
    description: "Pour ceux qui veulent des résultats sérieux.",
    prices: { "EUR" => 1999, "USD" => 1999 },
    features: [
      "Scans & coach IA illimités",
      "Tout de Premium inclus",
      "Modèle IA premium (plus puissant)",
      "Planning regénéré chaque semaine",
      "Rapport quotidien personnalisé",
      "Badge VIP exclusif",
      "Accès early adopter aux nouvelles features",
      "Support dédié — réponse < 24h garantie"
    ],
    translations: {
      "en" => {
        "name" => "VIP", "description" => "For those who want serious results.",
        "cta_label" => "Go VIP",
        "features" => [
          "Unlimited AI scans & coach", "Everything in Premium",
          "Premium AI model (more powerful)", "Weekly regenerated meal plan",
          "Daily personalized report", "Exclusive VIP badge",
          "Early adopter access to new features", "Dedicated support — response < 24h guaranteed"
        ]
      },
      "fr" => {
        "name" => "VIP", "description" => "Pour ceux qui veulent des résultats sérieux.",
        "cta_label" => "Passer VIP",
        "features" => [
          "Scans & coach IA illimités", "Tout de Premium inclus",
          "Modèle IA premium (plus puissant)", "Planning regénéré chaque semaine",
          "Rapport quotidien personnalisé", "Badge VIP exclusif",
          "Accès early adopter aux nouvelles features", "Support dédié — réponse < 24h garantie"
        ]
      }
    }
  },

  # ── VIP annuel (-33%) ─────────────────────────────────────────────
  {
    name: "VIP", slug: "vip-yearly", position: 4, status: "active",
    billing_frequency: "yearly", price_ariary: 80_000,
    badge: nil, savings_percent: 33,
    description: "Pour ceux qui veulent des résultats sérieux.",
    prices: { "EUR" => 15999, "USD" => 15999 },
    features: [
      "Scans & coach IA illimités",
      "Tout de Premium inclus",
      "Modèle IA premium (plus puissant)",
      "Planning regénéré chaque semaine",
      "Rapport quotidien personnalisé",
      "Badge VIP exclusif",
      "Accès early adopter aux nouvelles features",
      "Support dédié — réponse < 24h garantie"
    ],
    translations: {
      "en" => {
        "name" => "VIP", "description" => "For those who want serious results.",
        "cta_label" => "Go VIP — Save 33%"
      },
      "fr" => {
        "name" => "VIP", "description" => "Pour ceux qui veulent des résultats sérieux.",
        "cta_label" => "Passer VIP — -33%"
      }
    }
  }
]

plans_data.each do |attrs|
  plan = Plan.find_or_initialize_by(slug: attrs[:slug])
  plan.assign_attributes(attrs.except(:features, :features_excluded, :operators, :translations, :prices))
  plan.features          = attrs[:features] || []
  plan.features_excluded = attrs[:features_excluded] || []
  plan.operators         = attrs[:operators] || []
  plan.prices            = attrs[:prices] || {}
  plan.translations      = attrs[:translations] || {}
  plan.save!
  price_str = plan.prices["EUR"].to_i == 0 ? "Gratuit" : "#{plan.price_formatted}/#{plan.frequency_label.downcase}"
  puts "✓ Plan : #{plan.name} #{plan.billing_frequency} — #{price_str}"
end
