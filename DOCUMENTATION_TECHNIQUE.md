# Documentation Technique — DietVision Dashboard

**Version :** 1.0  
**Date :** Avril 2026  
**Projet :** dietvision_dashboard  

---

## 1. Vue d'ensemble

**DietVision Dashboard** est le backend Ruby on Rails 8 de l'application mobile DietVision. Il fournit :

- Une **API REST** (`/api/v1`) pour l'application mobile Flutter
- Un **dashboard administrateur** web (`/admin`) pour la gestion de l'activité

### Informations générales

| Champ | Valeur |
|---|---|
| Framework | Ruby on Rails 8.0 |
| Base de données | SQLite (développement), PostgreSQL (production) |
| Langage | Ruby 3.3+ |
| API | REST JSON |
| Authentification | JWT (mobile), Session (admin) |

---

## 2. Architecture

```
┌─────────────────────────────────────────────┐
│         Application Mobile Flutter           │
└─────────────────┬─────────────────────────┘
                  │ HTTPS + JWT
                  ▼
┌─────────────────────────────────────────────┐
│         DietVision Dashboard               │
│  ┌─────────────┐   ┌───────────────────┐  │
│  │ API /api/v1 │   │ Admin /admin       │  │
│  └─────────────┘   └───────────────────┘  │
└─────────┬───────────────────┬───────────┘
          │                   │
          ▼                   ▼
    ┌──────────┐       ┌──────────┐
    │OpenRouter│       │ Stripe   │
    │   IA     │       │Paiement │
    └──────────┘       └──────────┘
```

---

## 3. Structure des fichiers

```
dietvision_dashboard/
├── app/
│   ├── controllers/
│   │   ├── api/v1/          # API REST mobile
│   │   │   ├── admin/         # Dashboard admin
│   │   │   └── concerns/
│   ├── models/               # ActiveRecord
│   │   ├── user.rb
│   │   ├── subscription.rb
│   │   ├── payment.rb
│   │   ├── api_usage.rb
│   │   ├── plan.rb
│   │   ├── promo_code.rb
│   │   ├── app_config.rb
│   │   └── admin_user.rb
│   ├── services/            # Logique métier
│   │   ├── openrouter_service.rb
│   │   ├── stripe_service.rb
│   │   └── cinetpay_service.rb
│   ├── views/
│   │   ├── admin/           # Vues ERB + Tailwind
│   │   └── layouts/
│   └── helpers/
├── config/
│   ├── routes.rb
│   ├── application.rb
│   └── initializers/
├── db/
│   ├── migrate/             # Migrations
│   └── schema.rb
└── Gemfile
```

---

## 4. Modèle de données

### Tables principales

| Table | Description |
|---|---|
| `users` | Utilisateurs de l'app mobile |
| `subscriptions` | Abonnements actifs |
| `payments` | Transactions paiement |
| `api_usages` | Suivi usage API IA |
| `plans` | Plans tarifaires (monthly, yearly) |
| `promo_codes` | Codes réduction |
| `admin_users` | Comptes administrateurs |
| `app_configs` | Configuration applicative |
| `admin_logs` | Journal d'audit des actions admin |

### Schéma (extrait)

```ruby
# users
t.string :name
t.string :email
t.string :phone
t.string :country          # "CI" par défaut
t.string :status          # "active" | "suspended"
t.string :plan            # "free" | "premium"
t.datetime :subscription_expires_at
t.datetime :trial_ends_at
t.boolean :had_trial
t.text :fitai_profile     # JSON nutrition profile
t.text :planning_data    # JSON weekly planning
t.text :body_entries_data # JSON mesures corporelles

# subscriptions
t.integer :user_id
t.string :plan            # "monthly" | "yearly"
t.decimal :amount
t.string :status          # "pending" | "active" | "expired"
t.datetime :starts_at
t.datetime :expires_at
t.string :stripe_subscription_id

# payments
t.integer :user_id
t.integer :subscription_id
t.decimal :amount
t.string :provider        # "stripe" | "cinetpay" | "mtn" | "orange"
t.string :status         # "pending" | "success" | "failed"
t.string :transaction_id

# api_usages
t.integer :user_id
t.string :endpoint        # "analyze_food" | "coach_chat"
t.string :model
t.integer :input_tokens
t.integer :output_tokens
t.decimal :cost_usd
t.integer :duration_ms
t.string :status         # "success" | "error"

# plans
t.string :name
t.string :slug
t.integer :price_ariary
t.text :features_json
t.text :prices_json      # {"monthly": 2000, "yearly": 18000}
t.string :stripe_price_id

# app_configs
t.string :key            # "openrouter_api_key", "stripe_secret_key", etc.
t.text :value
```

---

## 5. API REST Mobile (`/api/v1`)

### Endpoints

| Méthode | Route | Auth | Description |
|---|---|---|---|
| `POST` | `/auth/register` | ❌ | Inscription |
| `POST` | `/auth/login` | ❌ | Connexion |
| `GET` | `/auth/me` | ✅ | Profil token |
| `POST` | `/auth/refresh` | ✅ | Renouveler token |
| `POST` | `/ai/analyze` | ✅ | Analyse photo ia |
| `POST` | `/ai/coach` | ✅ | Coach nutrition |
| `GET` | `/plans` | ❌ | Liste plans |
| `POST` | `/promo_codes/validate` | ✅ | Valider code promo |
| `POST` | `/payments/subscribe` | ✅ | Initier paiement |
| `GET` | `/payments/status/:id` | ✅ | Statut paiement |
| `POST` | `/payments/webhook` | ❌ | Webhook Stripe |
| `GET` | `/payments` | ✅ | Historique |
| `GET` | `/profile` | ✅ | Profil utilisateur |
| `PATCH` | `/profile` | ✅ | Mettre à jour profil |
| `GET` | `/profile/usage` | ✅ | Quota consommation |
| `GET` | `/user/fitai` | ✅ | Profil nutrition |
| `PUT` | `/user/fitai` | ✅ | Mettre à jour profil |
| `GET` | `/user/planning` | ✅ | Planning hebdomadaire |
| `PUT` | `/user/planning` | ✅ | Mettre à jour planning |
| `GET` | `/user/body_entries` | ✅ | Mesures corporelles |
| `PUT` | `/user/body_entries` | ✅ | Sauvegarder mesures |
| `GET` | `/health` | ❌ | Health check |

### Authentification

- **JWT** avec header `Authorization: Bearer <token>`
- Token TTL : 30 jours
- Signature HS256 avec `Rails.application.secret_key_base`

---

## 6. Dashboard Administrateur (`/admin`)

### Routes

| Méthode | Route | Description |
|---|---|---|
| `GET` | `/admin` | Dashboard KPIs |
| `GET` | `/admin/login` | Connexion |
| `POST` | `/admin/login` | Authentifier |
| `DELETE` | `/admin/logout` | Déconnexion |
| `GET` | `/admin/users` | Liste utilisateurs |
| `GET` | `/admin/users/:id` | Fiche utilisateur |
| `PATCH` | `/admin/users/:id` | Modifier utilisateur |
| `POST` | `/admin/users/:id/suspend` | Suspendre |
| `POST` | `/admin/users/:id/activate` | Réactiver |
| `GET` | `/admin/plans` | Liste plans |
| `POST` | `/admin/plans` | Créer plan |
| `GET` | `/admin/trial` | Gestion essai |
| `GET` | `/admin/promo_codes` | Codes promo |
| `GET` | `/admin/payments` | Liste paiements |
| `GET` | `/admin/payments/:id` | Détail paiement |
| `POST` | `/admin/payments/:id/recheck` | Re-vérifier |
| `GET` | `/admin/configs` | Configuration |
| `POST` | `/admin/configs` | Sauvegarder config |
| `GET` | `/admin/api_usages` | Usage API |
| `GET` | `/admin/admin_logs` | Logs audit |

### KPIs Dashboard

- Total utilisateurs
- Utilisateurs premium
- Revenus du mois
- Appels API aujourd'hui
- Revenus totaux
- Nouveaux ce mois

---

## 7. Services Métier

### OpenrouterService

Proxy vers OpenRouter pour l'analyse d'images et le chat coach.

- ** Méthodes :
  - `analyze_food(base64_image, model)` → Analyse photo alimentaire
  - `coach_chat(messages, profile)` → Chat coach IA
- Suivi usage : tokens, coût USD, durée

### StripeService

Intégration Stripe pour les paiements par carte.

- `find_or_create_customer(user)` → Customer Stripe
- `create_checkout_session(user:, plan:)` → URL paiement
- `handle_event(event)` → Webhook handler

### CinetpayService

Intégration CinetPay pour Mobile Money (hors périmètre actuel, historique).

---

## 8. Modèles ActiveRecord

### User

```ruby
class User < ApplicationRecord
  has_secure_password
  has_many :subscriptions
  has_many :payments
  has_many :api_usages

  # Scopes
  scope :in_trial
  scope :active_users
  scope :new_this_month

  # Méthodes
  def premium?
  def in_trial?
  def trial_days_remaining
  def active_subscription
  def total_spent
  def api_calls_this_month
end
```

### Subscription

- Gestion du cycle de vie d'abonnement
- Statuts : `pending` → `active` → `expired`
- Intégration Stripe via `stripe_subscription_id`

### Payment

- Gestion des transactions
- Statuts : `pending` → `success` / `failed`
- Providers : `stripe`, `cinetpay`, etc.

### ApiUsage

- Tracking appel API IA
- Coût estimé en USD basé sur le modèle

### Plan

- Plans tarifaires configurables
- Prix flexibles (JSON : `{ "monthly": 2000, "yearly": 18000 }`)
- Intégration Stripe via `stripe_price_id`

---

## 9. Configuration

### Variables d'environnement

| Variable | Description |
|---|---|
| `SECRET_KEY_BASE` | Clé Rails |
| `DATABASE_URL` | URL PostgreSQL |
| `RAILS_ENV` | `production` |

### AppConfig (BDD)

Les clés API et configurations sont stockées en BDD (`app_configs`) et accessibles via :

```ruby
AppConfig.openrouter_api_key
AppConfig.stripe_secret_key
AppConfig.free_daily_limit
AppConfig.premium_daily_limit
```

---

## 10. Dépendances (Gemfile)

| Gem | Usage |
|---|---|
| `rails` ~> 8.0 | Framework |
| `pg` | PostgreSQL |
| `jwt` | Authentification JWT |
| `bcrypt` | Hash mots de passe |
| `pagy` | Pagination |
| `stripe` | Paiements Stripe |
| `tailwindcss-rails` | CSS |
| `stimulus-rails` | JavaScript |
| `propshaft` | Assets |
| `faraday` | HTTP client |
| `cinetpay` (optionnel) | Mobile Money |

---

## 11. Commandes utiles

```bash
# Installation
bin/setup

# Démarrage développement
bin/dev

# Migrations
rails db:migrate
rails db:seed

# Assets
rails tailwindcss:build

# Tests
rails test

# Rubocop
rubocop
```

---

## 12. Points d'intégration

### Application mobile Flutter

- Base URL : `https://api.dietvision.app/api/v1`
- Auth header : `Authorization: Bearer <jwt_token>`
- Endpoints principaux : `/auth/*`, `/ai/*`, `/payments/*`, `/profile/*`

### Stripe Dashboard

- Stripe Customer créé à la première commande
- Webhook : `/api/v1/payments/webhook`

### OpenRouter

- Clé API stockée en `app_configs`
- Modèles supportés : `google/gemini-2.0-flash-001`, `openai/gpt-4o-mini`, etc.

---

*Document généré le 28 avril 2026 — DietVision Dashboard*