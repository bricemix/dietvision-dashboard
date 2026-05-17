Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # ─── API mobile ────────────────────────────────────────────────
  namespace :api do
    namespace :v1 do
      # Auth
      post   "auth/register",  to: "auth#register"
      post   "auth/login",     to: "auth#login"
      get    "auth/me",        to: "auth#me"
      post   "auth/refresh",   to: "auth#refresh"

      # IA
      post   "ai/analyze",     to: "ai#analyze"
      post   "ai/coach",       to: "ai#coach"

      # Plans (public)
      get    "plans",          to: "plans#index"

      # Codes promo
      post   "promo_codes/validate", to: "promo_codes#validate"

      # Paiements (Stripe)
      post   "payments/subscribe",              to: "payments#subscribe"
      get    "payments/status/:transaction_id", to: "payments#status", as: :payment_status
      post   "payments/webhook",               to: "payments#webhook", as: :payments_webhook
      get    "payments",                       to: "payments#index"

      # Profil
      get    "profile",        to: "profile#show"
      patch  "profile",        to: "profile#update"
      get    "profile/usage",  to: "profile#usage"

      # FitAI data (nutrition profile + planning)
      get    "user/fitai",     to: "profile#fitai_show"
      put    "user/fitai",     to: "profile#fitai_update"
      put    "user/profile",   to: "profile#fitai_update"   # alias used by Flutter
      put    "user/planning",  to: "profile#planning_update"
      get    "user/planning",  to: "profile#planning_show"

      # Health check
      get    "health",         to: "health#show"
    end
  end

  # ─── Admin dashboard ──────────────────────────────────────────
  namespace :admin do
    # Authentification
    get    "login",  to: "sessions#new",     as: :login
    post   "login",  to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout

    # Dashboard
    root to: "dashboard#index", as: :dashboard

    # Utilisateurs
    resources :users, only: %i[index show update] do
      member do
        post :suspend
        post :activate
        post :extend_subscription
        post :gift_access
      end
    end

    # Plans tarifaires
    resources :plans do
      member do
        post :activate
        post :deactivate
      end
    end

    # Période d'essai
    get  "trial",        to: "trial#index",         as: :trial
    post "trial/config", to: "trial#update_config",  as: :trial_config
    post "trial/extend", to: "trial#extend_user_trial", as: :trial_extend

    # Codes promo
    resources :promo_codes do
      member     { post :disable }
      collection { post :bulk_generate }
    end

    # Paiements
    resources :payments, only: %i[index show] do
      member { post :recheck }
    end

    # Configuration API
    get  "configs",                    to: "configs#index",          as: :configs
    post "configs",                    to: "configs#update"
    get  "configs/test_openrouter",    to: "configs#test_openrouter", as: :test_openrouter

    # Utilisation API
    resources :api_usages, only: %i[index]

    # Logs admin (audit trail)
    resources :admin_logs, only: %i[index]
  end

  # Redirection racine vers l'admin
  root to: redirect("/admin")
end
