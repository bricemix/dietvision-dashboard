Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # ─── API mobile ────────────────────────────────────────────────
  namespace :api do
    namespace :v1 do
      # Auth
      post   "auth/register",          to: "auth#register"
      post   "auth/login",             to: "auth#login"
      delete "auth/logout",            to: "auth#logout"
      get    "auth/me",                to: "auth#me"
      post   "auth/refresh",           to: "auth#refresh"
      post   "auth/send_verification", to: "auth#send_verification"
      post   "auth/verify_email",      to: "auth#verify_email"
      post   "auth/forgot_password",   to: "auth#forgot_password"
      post   "auth/reset_password",    to: "auth#reset_password"

      # IA
      post   "ai/analyze",     to: "ai#analyze"
      post   "ai/coach",       to: "ai#coach"
      post   "ai/dishes",      to: "ai#dishes"

      # Plans (public)
      get    "plans",          to: "plans#index"

      # Config publique (trial days, etc.)
      get    "config",             to: "config#show"

      # Documents légaux (public — pas d'auth)
      get    "legal/rgpd",    to: "legal#rgpd"
      get    "legal/cgu",     to: "legal#cgu"
      get    "legal/regions", to: "legal#regions"

      # Codes promo
      post   "promo_codes/validate", to: "promo_codes#validate"

      # Paiements (Stripe)
      post   "payments/subscribe",              to: "payments#subscribe"
      post   "payments/verify",                 to: "payments#verify"
      get    "payments/webhook-status",         to: "payments#webhook_status"
      get    "payments/status/:transaction_id", to: "payments#status", as: :payment_status
      post   "payments/webhook",               to: "payments#webhook", as: :payments_webhook
      get    "payments",                       to: "payments#index"

      # Profil
      get    "profile",        to: "profile#show"
      patch  "profile",        to: "profile#update"
      get    "profile/usage",  to: "profile#usage"

      # FitAI data (nutrition profile + planning + mesures corporelles)
      get    "user/fitai",         to: "profile#fitai_show"
      put    "user/fitai",         to: "profile#fitai_update"
      put    "user/profile",       to: "profile#fitai_update"   # alias used by Flutter
      get    "user/planning",      to: "profile#planning_show"
      put    "user/planning",      to: "profile#planning_update"
      get    "user/body_entries",  to: "profile#body_entries_show"
      put    "user/body_entries",  to: "profile#body_entries_update"
      get    "user/meals",         to: "profile#meals_show"
      put    "user/meals",         to: "profile#meals_update"

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
    resources :users, only: %i[index show update new create] do
      member do
        post   :suspend
        post   :activate
        post   :extend_subscription
        post   :gift_access
        delete :destroy
        get    :data           # Voir toutes les données de l'utilisateur
        delete :clear_data     # Supprimer un type de données
      end
      collection do
        delete :destroy_all
      end
    end

    # Plans tarifaires
    resources :plans do
      member do
        post :activate
        post :deactivate
        post :sync_stripe
        post :send_report_test   # Envoyer un rapport test à l'admin
      end
      collection do
        post :sync_all_stripe
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
      member     { post :recheck }
      collection { post :repair_stripe_pending }
    end

    # Configuration API
    get  "configs",                    to: "configs#index",          as: :configs
    post "configs",                    to: "configs#update"
    get  "configs/test_openrouter",    to: "configs#test_openrouter", as: :test_openrouter
    get  "configs/test_stripe",        to: "configs#test_stripe",     as: :test_stripe
    get  "configs/test_resend",        to: "configs#test_resend",     as: :test_resend
    get  "configs/test_api",           to: "configs#test_api",        as: :test_api

    # Utilisation API
    resources :api_usages, only: %i[index]

    # Logs admin (audit trail)
    resources :admin_logs, only: %i[index]

    # Logs serveur (puma.log)
    get    "server_logs",          to: "server_logs#index",    as: :server_logs
    get    "server_logs/download", to: "server_logs#download", as: :download_server_logs
    delete "server_logs/clear",    to: "server_logs#clear",    as: :clear_server_logs

    # Documents légaux (RGPD / CGU)
    resources :legal_documents, only: %i[index create destroy] do
      member { post :activate }
    end
  end

  # Pages de retour Stripe Checkout (success / cancel)
  get  'payment/success', to: 'payment_pages#success', as: :payment_success
  get  'payment/cancel',  to: 'payment_pages#cancel',  as: :payment_cancel

  # Redirection racine vers l'admin
  root to: redirect("/admin")
end
