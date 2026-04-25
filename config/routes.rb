Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # ─── API mobile ───────────────────────────────────────────────────
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

      # Paiements
      post   "payments/initiate",              to: "payments#initiate"
      get    "payments/status/:transaction_id", to: "payments#status", as: :payment_status
      post   "payments/webhook",               to: "payments#webhook", as: :payments_webhook
      get    "payments",                       to: "payments#index"

      # Profil
      get    "profile",        to: "profile#show"
      patch  "profile",        to: "profile#update"
      get    "profile/usage",  to: "profile#usage"
    end
  end

  # ─── Admin dashboard ──────────────────────────────────────────────
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
      end
    end

    # Paiements
    resources :payments, only: %i[index show] do
      member { post :recheck }
    end

    # Configuration API
    get  "configs",  to: "configs#index",          as: :configs
    post "configs",  to: "configs#update"
    get  "configs/test_openrouter", to: "configs#test_openrouter", as: :test_openrouter

    # Utilisation API
    resources :api_usages, only: %i[index]
  end

  # Redirection racine vers l'admin
  root to: redirect("/admin")
end
