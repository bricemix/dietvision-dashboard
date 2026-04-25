# Cahier des Charges — DietVision Dashboard & API Backend

**Version :** 1.0  
**Date :** Avril 2026  
**Auteur :** Équipe DietVision  
**Statut :** En développement

---

## Table des matières

1. [Présentation du projet](#1-présentation-du-projet)
2. [Contexte et objectifs](#2-contexte-et-objectifs)
3. [Périmètre fonctionnel](#3-périmètre-fonctionnel)
4. [Architecture technique](#4-architecture-technique)
5. [API Mobile (REST)](#5-api-mobile-rest)
6. [Module Authentification](#6-module-authentification)
7. [Module IA — Proxy OpenRouter](#7-module-ia--proxy-openrouter)
8. [Module Paiement Mobile Money](#8-module-paiement-mobile-money)
9. [Dashboard Administrateur](#9-dashboard-administrateur)
10. [Modèle de données](#10-modèle-de-données)
11. [Sécurité](#11-sécurité)
12. [Performance et scalabilité](#12-performance-et-scalabilité)
13. [Déploiement](#13-déploiement)
14. [Roadmap](#14-roadmap)

---

## 1. Présentation du projet

**DietVision Dashboard** est le backend centralisé de l'application mobile DietVision. Il remplit deux rôles distincts :

- **API REST** consommée par l'application mobile Flutter — gestion des utilisateurs, proxy IA, paiements
- **Interface d'administration web** permettant à l'équipe DietVision de piloter l'activité : utilisateurs, revenus, consommation API, configuration

### Informations générales

| Champ | Valeur |
|---|---|
| Nom du produit | DietVision Dashboard |
| Type | Application web Rails + API REST |
| Langages | Ruby 3.3+, HTML/ERB, Tailwind CSS, JavaScript |
| Framework | Ruby on Rails 8.0 |
| Base de données | SQLite (développement) → PostgreSQL (production) |
| URL dashboard | `https://dashboard.dietvision.app` |
| URL API | `https://api.dietvision.app/api/v1` |

---

## 2. Contexte et objectifs

### 2.1 Contexte

L'application mobile **DietVision** permet aux utilisateurs d'analyser leurs repas par photo grâce à l'IA, de suivre leurs apports nutritionnels et de bénéficier d'un coaching personnalisé. La v1 de l'app appelait directement OpenRouter depuis le téléphone, exposant la clé API et ne permettant aucun contrôle d'accès.

La v2 introduit ce backend centralisé pour :
- **Sécuriser** la clé API OpenRouter (jamais exposée côté client)
- **Monétiser** l'application via des abonnements Mobile Money
- **Contrôler** l'usage (quotas journaliers par plan)
- **Analyser** l'activité en temps réel via le dashboard

### 2.2 Objectifs

| Priorité | Objectif |
|---|---|
| 🔴 Critique | Authentification utilisateur sécurisée (JWT) |
| 🔴 Critique | Proxy OpenRouter avec tracking des coûts |
| 🔴 Critique | Paiement Mobile Money (CinetPay) |
| 🟠 Important | Dashboard admin complet |
| 🟠 Important | Gestion des quotas par plan |
| 🟡 Utile | Statistiques d'utilisation détaillées |
| 🟡 Utile | Configuration à chaud sans redémarrage |

### 2.3 Utilisateurs cibles

| Profil | Description |
|---|---|
| **Utilisateur mobile** | Abonné DietVision — utilise l'app Flutter, interagit via l'API |
| **Administrateur** | Équipe DietVision — accède au dashboard web pour gérer l'activité |

---

## 3. Périmètre fonctionnel

### 3.1 Fonctionnalités incluses (v1)

#### Côté API mobile
- [x] Inscription / Connexion avec email + mot de passe
- [x] Token JWT (30 jours, refresh possible)
- [x] Analyse photo alimentaire via OpenRouter (proxy sécurisé)
- [x] Chat coach nutritionnel via OpenRouter
- [x] Quota journalier selon le plan (free / premium)
- [x] Initiation de paiement Mobile Money (CinetPay)
- [x] Webhook de confirmation de paiement
- [x] Consultation du profil et de l'usage

#### Côté dashboard admin
- [x] Connexion sécurisée par session
- [x] Vue d'ensemble (KPIs : utilisateurs, revenus, appels API)
- [x] Liste des utilisateurs avec filtres et pagination
- [x] Fiche détaillée d'un utilisateur (abonnements, paiements, appels API)
- [x] Suspension / Réactivation d'un compte
- [x] Liste des paiements avec filtres
- [x] Re-vérification manuelle d'un paiement via CinetPay
- [x] Liste des appels API avec coûts
- [x] Configuration des clés API (OpenRouter, CinetPay) via interface web
- [x] Test de connexion OpenRouter depuis le dashboard

### 3.2 Fonctionnalités hors périmètre (v1)

- Authentification OAuth (Google, Apple)
- Application mobile web (PWA)
- Notifications push
- Export CSV / PDF des données
- Multi-administrateurs avec rôles fins
- Système de tickets support

---

## 4. Architecture technique

### 4.1 Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Mobile Flutter                │
│                  (iOS / Android — DietVision)                │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTPS + JWT
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              DietVision Dashboard (Rails 8)                  │
│                                                              │
│  ┌────────────────────┐   ┌──────────────────────────────┐  │
│  │   API REST /api/v1  │   │   Admin Dashboard /admin     │  │
│  │                    │   │   (Session + Tailwind CSS)   │  │
│  │  Auth · IA         │   │                              │  │
│  │  Payments · Profile│   │  Users · Payments · Config   │  │
│  └────────┬───────────┘   └──────────────────────────────┘  │
│           │                                                  │
│  ┌────────▼───────────────────────────────────────────────┐  │
│  │                    Services Ruby                        │  │
│  │   OpenrouterService      CinetpayService               │  │
│  └────────┬───────────────────────┬────────────────────── ┘  │
│           │                       │                          │
└───────────┼───────────────────────┼──────────────────────────┘
            │                       │
            ▼                       ▼
   ┌─────────────────┐    ┌──────────────────┐
   │ OpenRouter API  │    │  CinetPay API    │
   │ (IA — LLM/Vision│    │  (Mobile Money)  │
   └─────────────────┘    └──────────────────┘
```

### 4.2 Stack technique

| Composant | Technologie | Version |
|---|---|---|
| Framework web | Ruby on Rails | 8.0.4 |
| Langage | Ruby | 3.3+ |
| Base de données | SQLite → PostgreSQL | — |
| CSS | Tailwind CSS via `tailwindcss-rails` | 4.x |
| JavaScript | Importmap + Stimulus + Turbo | — |
| Serveur HTTP | Puma | 6.x |
| Authentification API | JWT (HS256, 30j) | gem `jwt ~> 2.9` |
| Authentification admin | Session cookie Rails | — |
| Client HTTP | Faraday | 2.12+ |
| Pagination | Pagy | 9.x |
| Graphiques | Chartkick + Groupdate | — |
| CORS | Rack::Cors | — |
| Assets | Propshaft | — |

### 4.3 Structure des dossiers

```
dietvision_dashboard/
├── app/
│   ├── controllers/
│   │   ├── api/v1/              # Contrôleurs API REST
│   │   │   ├── base_controller.rb
│   │   │   ├── auth_controller.rb
│   │   │   ├── ai_controller.rb
│   │   │   ├── payments_controller.rb
│   │   │   └── profile_controller.rb
│   │   ├── admin/               # Contrôleurs dashboard
│   │   │   ├── base_controller.rb
│   │   │   ├── sessions_controller.rb
│   │   │   ├── dashboard_controller.rb
│   │   │   ├── users_controller.rb
│   │   │   ├── payments_controller.rb
│   │   │   ├── api_usages_controller.rb
│   │   │   └── configs_controller.rb
│   │   └── concerns/
│   │       └── jwt_authenticatable.rb
│   ├── models/                  # Modèles ActiveRecord
│   ├── services/                # Services métier
│   │   ├── openrouter_service.rb
│   │   └── cinetpay_service.rb
│   ├── views/
│   │   ├── layouts/admin.html.erb
│   │   └── admin/               # Vues ERB Tailwind
│   └── helpers/
│       ├── application_helper.rb
│       └── admin_helper.rb
├── config/
│   ├── routes.rb
│   ├── application.rb
│   └── initializers/
├── db/
│   ├── migrate/
│   └── seeds.rb
└── Gemfile
```

---

## 5. API Mobile (REST)

### 5.1 Conventions

- **Base URL :** `https://api.dietvision.app/api/v1`
- **Format :** JSON (`Content-Type: application/json`)
- **Authentification :** `Authorization: Bearer <jwt_token>` (sauf endpoints publics)
- **Codes de retour :** standard HTTP (200, 201, 400, 401, 403, 422, 429, 500)

### 5.2 Tableau des endpoints

#### Authentification

| Méthode | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/auth/register` | ❌ | Inscription |
| `POST` | `/auth/login` | ❌ | Connexion |
| `GET` | `/auth/me` | ✅ | Profil depuis token |
| `POST` | `/auth/refresh` | ✅ | Renouvellement token |

#### IA

| Méthode | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/ai/analyze` | ✅ | Analyse photo alimentaire |
| `POST` | `/ai/coach` | ✅ | Message au coach IA |

#### Paiements

| Méthode | Endpoint | Auth | Description |
|---|---|---|---|
| `POST` | `/payments/initiate` | ✅ | Initier un paiement |
| `GET` | `/payments/status/:id` | ✅ | Statut d'une transaction |
| `POST` | `/payments/webhook` | ❌ | Callback CinetPay |
| `GET` | `/payments` | ✅ | Historique des paiements |

#### Profil

| Méthode | Endpoint | Auth | Description |
|---|---|---|---|
| `GET` | `/profile` | ✅ | Profil complet |
| `PATCH` | `/profile` | ✅ | Mise à jour profil |
| `GET` | `/profile/usage` | ✅ | Quota et consommation |

### 5.3 Exemples de requêtes / réponses

#### Inscription

```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "user": {
    "name": "Kouamé Yao",
    "email": "kouame@example.ci",
    "password": "secret123",
    "phone": "+2250102030405",
    "country": "CI"
  }
}
```

```json
HTTP 201 Created
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 42,
    "name": "Kouamé Yao",
    "email": "kouame@example.ci",
    "plan": "free",
    "premium": false,
    "subscription_expires_at": null
  }
}
```

#### Analyse photo

```http
POST /api/v1/ai/analyze
Authorization: Bearer eyJhbGci...
Content-Type: application/json

{
  "image": "<base64 JPEG>",
  "model": "google/gemini-2.0-flash-001"
}
```

```json
HTTP 200 OK
{
  "name": "Riz sauce graine",
  "estimatedGrams": 350,
  "calories": 520,
  "protein": 18.5,
  "carbs": 72.0,
  "fat": 14.2,
  "fiber": 3.1,
  "vitamins": "B1, B6, E",
  "minerals": "Fer, Potassium, Magnésium",
  "healthScore": 7,
  "tip": "Riche en glucides complexes, idéal après l'effort."
}
```

#### Quota dépassé

```json
HTTP 429 Too Many Requests
{
  "error": "Limite journalière atteinte (5/5)",
  "upgrade_required": true
}
```

#### Initiation paiement

```http
POST /api/v1/payments/initiate
Authorization: Bearer eyJhbGci...
Content-Type: application/json

{
  "plan": "monthly",
  "phone": "+2250102030405",
  "name": "Kouamé Yao"
}
```

```json
HTTP 201 Created
{
  "payment_url": "https://checkout.cinetpay.com/pay?token=abc123",
  "transaction_id": "DV-A1B2C3D4E5F6"
}
```

---

## 6. Module Authentification

### 6.1 Utilisateurs mobiles (JWT)

**Inscription :**
- Champs requis : `name`, `email`, `password`, `phone`, `country`
- Validation email (regex RFC) et unicité
- Mot de passe stocké avec `bcrypt` (has_secure_password)
- Token JWT signé avec `Rails.application.secret_key_base` (HS256)
- TTL : 30 jours

**Structure du payload JWT :**
```json
{
  "user_id": 42,
  "exp": 1751234567,
  "iat": 1748642567
}
```

**Vérification :**
- Header `Authorization: Bearer <token>` sur toutes les routes protégées
- Vérification expiration, signature, existence de l'utilisateur
- Rejet si compte suspendu

### 6.2 Administrateurs (Session)

- Login par email + mot de passe
- Session stockée côté serveur (cookie signé Rails)
- Redirection vers `/admin/login` si non authentifié
- Déconnexion par suppression de session (`session.delete(:admin_id)`)
- Enregistrement de `last_login_at` à chaque connexion

### 6.3 Politique de sécurité

- Pas de rate limiting en v1 (à ajouter en v2 avec `rack-attack`)
- HTTPS obligatoire en production
- Tokens non révocables en v1 (liste noire à ajouter en v2)

---

## 7. Module IA — Proxy OpenRouter

### 7.1 Rôle du proxy

Le backend agit comme intermédiaire entre l'app mobile et OpenRouter :
- La **clé API OpenRouter** n'est jamais transmise au client
- Chaque appel est **comptabilisé** (tokens, coût estimé, durée)
- Le **modèle** peut être forcé ou laissé au choix de l'app
- Les **quotas journaliers** sont vérifiés avant chaque requête

### 7.2 Flux analyse photo

```
App mobile → POST /ai/analyze (base64 image)
    → Vérification JWT
    → Vérification quota journalier
    → OpenrouterService.analyze_food(base64)
        → POST openrouter.ai/api/v1/chat/completions
        → Modèle vision (gemini-2.0-flash-001)
        → Réponse JSON nutritionnelle
    → ApiUsage.create!(tokens, coût, durée)
    → Retour JSON à l'app
```

### 7.3 Modèles disponibles

| Modèle | Usage | Coût input (1M tokens) | Coût output (1M tokens) |
|---|---|---|---|
| `google/gemini-2.0-flash-001` | Vision + Texte (défaut) | $0.075 | $0.30 |
| `openai/gpt-4o-mini` | Texte léger | $0.15 | $0.60 |
| `openai/gpt-4o` | Texte premium | $2.50 | $10.00 |

> Les modèles et tarifs sont configurables dans `AppConfig` via le dashboard.

### 7.4 Prompt d'analyse alimentaire

Le prompt demande à l'IA de retourner un objet JSON strict avec les champs :
`name`, `estimatedGrams`, `calories`, `protein`, `carbs`, `fat`, `fiber`, `vitamins`, `minerals`, `healthScore`, `tip`

En cas de réponse non-JSON (markdown, explication), le service nettoie et re-parse automatiquement.

### 7.5 Quotas journaliers

| Plan | Appels/jour |
|---|---|
| Gratuit | 5 (configurable) |
| Premium | 100 (configurable) |

La limite est vérifiée en temps réel via `ApiUsage.where(user:).today.count`.

---

## 8. Module Paiement Mobile Money

### 8.1 Opérateurs supportés via CinetPay

| Opérateur | Pays |
|---|---|
| Orange Money | Côte d'Ivoire, Sénégal, Mali, Cameroun |
| MTN Mobile Money | Côte d'Ivoire, Cameroun |
| Moov Money | Côte d'Ivoire |
| Wave | Sénégal |
| Free Money | Sénégal |

### 8.2 Plans d'abonnement

| Plan | Prix | Durée | Accès |
|---|---|---|---|
| **Mensuel** | 2 000 XOF | 1 mois | 100 appels IA/jour |
| **Annuel** | 18 000 XOF | 12 mois | 100 appels IA/jour |

> Le plan annuel représente une économie de 10 % par rapport à 12 mois.

### 8.3 Flux de paiement

```
1. App → POST /payments/initiate { plan, phone, name }
2. Backend → Subscription(pending) + Payment(pending) en BDD
3. Backend → CinetPay API : initiate_payment()
4. CinetPay → Retourne payment_url
5. Backend → Retourne { payment_url, transaction_id } à l'app
6. App → Ouvre payment_url dans un WebView / navigateur
7. Utilisateur → Valide le paiement sur son téléphone (USSD/app opérateur)
8. CinetPay → POST /payments/webhook { cpm_trans_id, status }
9. Backend → CinetpayService.check_payment() pour confirmation
10. Backend → payment.mark_success!() → subscription.activate!()
11. App → GET /payments/status/:id pour vérifier (polling ou deep link)
```

### 8.4 États d'un paiement

```
pending → success
        → failed
success → (terminal)
failed  → (terminal)
```

### 8.5 Idempotence du webhook

Le webhook CinetPay peut être appelé plusieurs fois. Le backend vérifie si le paiement est déjà `success` avant toute mise à jour et retourne toujours `HTTP 200` pour éviter les retentatives.

### 8.6 Re-vérification manuelle

L'admin peut déclencher une re-vérification d'un paiement `pending` depuis le dashboard via le bouton **"Re-vérifier via CinetPay"**, qui appelle directement `CinetpayService.check_payment()`.

---

## 9. Dashboard Administrateur

### 9.1 Accès

- URL : `https://dashboard.dietvision.app/admin`
- Authentification : email + mot de passe (session)
- Compte initial : `admin@dietvision.app` (créé via `db:seed`)

### 9.2 Pages et fonctionnalités

#### 9.2.1 Dashboard (`/admin`)

**KPIs affichés :**

| KPI | Description |
|---|---|
| Total utilisateurs | Nombre total d'inscrits |
| Utilisateurs premium | Plan actif non expiré |
| Revenus du mois | Somme des paiements `success` du mois |
| Appels API aujourd'hui | Total `ApiUsage.today` |
| Revenus totaux | Cumul historique |
| Appels API du mois | Avec coût estimé en USD |
| Nouveaux ce mois | Inscrits depuis le 1er du mois |

**Tableaux :**
- 5 derniers inscrits (nom, email, plan, date)
- 5 derniers paiements réussis (nom, montant, date)

#### 9.2.2 Utilisateurs (`/admin/users`)

**Liste :**
- Filtres : recherche textuelle (nom / email), plan, statut
- Colonnes : nom, email, pays, plan, statut, date inscription
- Actions rapides : Voir, Suspendre / Activer
- Pagination (25 par page)

**Fiche utilisateur (`/admin/users/:id`) :**
- Informations de profil complètes
- Statistiques : appels API du mois, total dépensé, nb abonnements
- Tableau des abonnements (plan, montant, dates, statut)
- 20 derniers appels API (endpoint, modèle, tokens, coût, statut)
- Actions : Suspendre / Réactiver

#### 9.2.3 Paiements (`/admin/payments`)

**Liste :**
- Filtres : statut, provider
- KPIs en haut : revenus totaux, du mois, en attente, échoués
- Colonnes : transaction ID, utilisateur, montant, provider, statut, date
- Pagination (25 par page)

**Détail paiement (`/admin/payments/:id`) :**
- Toutes les informations de la transaction
- Réponse brute du provider (JSON formaté)
- Bouton "Re-vérifier via CinetPay" (si statut `pending`)

#### 9.2.4 Utilisation API (`/admin/api_usages`)

**Liste :**
- Filtres : endpoint, statut
- KPIs : appels aujourd'hui, du mois, coût du mois
- Colonnes : utilisateur, endpoint, modèle, tokens in/out, coût, durée, statut, date
- Pagination (50 par page)

#### 9.2.5 Configuration (`/admin/configs`)

**Champs configurables :**

| Clé | Type | Description |
|---|---|---|
| `openrouter_api_key` | Password | Clé API OpenRouter |
| `openrouter_default_model` | Text | Modèle texte par défaut |
| `openrouter_vision_model` | Text | Modèle vision pour photos |
| `free_plan_daily_limit` | Number | Quota/jour plan gratuit |
| `premium_plan_daily_limit` | Number | Quota/jour plan premium |
| `cinetpay_api_key` | Password | Clé API CinetPay |
| `cinetpay_site_id` | Text | Site ID CinetPay |
| `app_name` | Text | Nom de l'application |
| `support_email` | Text | Email du support |

**Test de connexion OpenRouter :** Appel AJAX qui vérifie la clé API et liste les premiers modèles disponibles.

> Toute modification est appliquée **immédiatement** sans redémarrage du serveur (lecture via BDD à chaque requête).

### 9.3 Design et UX

- **Thème :** Sombre (dark mode) — `bg-gray-950` / `bg-gray-900`
- **Accent :** Vert émeraude (`emerald-400/600`) — cohérence avec l'app mobile
- **Framework CSS :** Tailwind CSS via `tailwindcss-rails`
- **Sidebar fixe** avec navigation principale
- **Badges de statut** colorés (`success`=vert, `pending`=jaune, `failed`=rouge)
- **Responsive :** mobile-friendly (grilles adaptatives)
- **Flash messages** pour les confirmations et erreurs

---

## 10. Modèle de données

### 10.1 Diagramme entité-relation

```
AdminUser
  id, name, email, password_digest, role, last_login_at

User
  id, name, email, phone, country, password_digest
  status [active|suspended]
  plan [free|premium]
  subscription_expires_at

User ──< Subscription
  id, user_id, plan [monthly|yearly]
  amount, currency [XOF]
  status [pending|active|expired|cancelled]
  starts_at, expires_at

User ──< Payment
  id, user_id, subscription_id (opt)
  amount, currency, provider [cinetpay|mtn|orange|wave]
  phone_number, transaction_id (unique)
  status [pending|success|failed|refunded]
  provider_ref, provider_response (JSON), paid_at

User ──< ApiUsage
  id, user_id, endpoint [analyze_food|coach_chat]
  model, input_tokens, output_tokens
  cost_usd (decimal 10,6), duration_ms
  status [success|error]

AppConfig
  id, key (unique), value (text), description
```

### 10.2 Migrations

| Fichier | Table |
|---|---|
| `20260425000001_create_admin_users.rb` | `admin_users` |
| `20260425000002_create_users.rb` | `users` |
| `20260425000003_create_subscriptions.rb` | `subscriptions` |
| `20260425000004_create_payments.rb` | `payments` |
| `20260425000005_create_api_usages.rb` | `api_usages` |
| `20260425000006_create_app_configs.rb` | `app_configs` |

### 10.3 Index BDD

| Table | Index |
|---|---|
| `users` | `email` (unique) |
| `admin_users` | `email` (unique) |
| `payments` | `transaction_id` (unique), `user_id`, `status` |
| `subscriptions` | `user_id`, `status` |
| `api_usages` | `user_id + created_at`, `created_at` |
| `app_configs` | `key` (unique) |

---

## 11. Sécurité

### 11.1 Authentification et autorisation

| Vecteur | Protection |
|---|---|
| Tokens JWT | Signés HS256 avec `secret_key_base`, TTL 30j |
| Mots de passe | Hachés `bcrypt` (coût adaptatif) |
| Sessions admin | Cookie signé Rails, HTTPOnly, SameSite=Lax |
| Routes API | `before_action :authenticate_user!` sur toutes les routes protégées |
| Routes admin | `before_action :authenticate_admin!` |
| Webhook CinetPay | Public mais idempotent + vérification systématique via API CinetPay |

### 11.2 Protection des données sensibles

| Donnée | Protection |
|---|---|
| Clé API OpenRouter | Stockée en BDD (chiffrée en production), jamais transmise au client |
| Clé API CinetPay | Idem |
| Mots de passe | Jamais stockés en clair (`has_secure_password`) |
| Réponses provider | Stockées en JSON dans `provider_response` (audit trail) |

### 11.3 CORS

- Headers CORS activés uniquement sur `/api/*`
- En développement : `origins "*"`
- En production : restreindre à l'origine de l'app mobile

### 11.4 Paramètres filtrés (logs)

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :password, :api_key, :secret, :token, :image
]
```

> Le champ `image` (base64) est filtré des logs pour éviter de saturer les fichiers de log.

### 11.5 Améliorations prévues (v2)

- Rate limiting avec `rack-attack` (anti-bruteforce login, anti-spam API)
- Révocation de tokens JWT (liste noire Redis)
- Audit log pour les actions admin sensibles
- 2FA pour l'accès admin
- Chiffrement des clés API en BDD (`attr_encrypted`)

---

## 12. Performance et scalabilité

### 12.1 Optimisations v1

| Optimisation | Description |
|---|---|
| `includes(:user)` | Eager loading pour éviter N+1 sur les listes |
| Indexes BDD | Sur `created_at`, `user_id`, `status`, `email` |
| `Faraday :retry` | Retry automatique (max 2) sur les appels OpenRouter et CinetPay |
| `Pagy` | Pagination côté BDD, jamais de `all` sans limite |
| `AppConfig` | Lecture BDD à chaque requête (cache possible en v2) |

### 12.2 Limites actuelles (SQLite)

SQLite est utilisé en développement. En production avec plusieurs workers Puma, utiliser **PostgreSQL** qui supporte les écritures concurrentes.

### 12.3 Capacité estimée (v1)

| Indicateur | Estimation |
|---|---|
| Utilisateurs actifs simultanés | ~100 |
| Appels API/minute | ~50 |
| Taille BDD à 6 mois | ~500 Mo |

---

## 13. Déploiement

### 13.1 Prérequis serveur

- Ruby 3.3+
- Node.js 20+ (build Tailwind)
- PostgreSQL 15+ (production)
- Nginx (reverse proxy)
- SSL/TLS (Let's Encrypt via Certbot)

### 13.2 Variables d'environnement

| Variable | Description |
|---|---|
| `SECRET_KEY_BASE` | Clé de signature Rails (JWT + sessions) |
| `DATABASE_URL` | URL PostgreSQL production |
| `RAILS_ENV` | `production` |
| `RAILS_LOG_TO_STDOUT` | `true` (pour les logs Docker / Heroku) |

> Les clés API (OpenRouter, CinetPay) sont gérées dans la table `app_configs` et configurables via le dashboard admin, **pas via les variables d'environnement**.

### 13.3 Commandes de mise en production

```bash
# Installation
bundle install --deployment
yarn build   # si assets JS

# Base de données
rails db:create db:migrate db:seed RAILS_ENV=production

# Assets
rails assets:precompile RAILS_ENV=production
rails tailwindcss:build  RAILS_ENV=production

# Démarrage
bundle exec puma -C config/puma.rb
```

### 13.4 Hébergement recommandé

| Option | Pour | Prix indicatif |
|---|---|---|
| Render.com | Démarrage rapide, PostgreSQL inclus | ~$7/mois |
| Fly.io | Performance, régions Afrique | ~$5/mois |
| VPS OVH / Hetzner | Contrôle total, moins cher à volume | ~$5/mois |

---

## 14. Roadmap

### v1.0 — MVP (en cours)
- [x] API REST complète (auth, IA, paiements, profil)
- [x] Dashboard admin (users, paiements, API usage, config)
- [x] Proxy OpenRouter sécurisé avec tracking coûts
- [x] Intégration CinetPay Mobile Money
- [x] Quotas journaliers par plan

### v1.1 — Stabilisation
- [ ] Tests automatisés (RSpec — modèles, services, API)
- [ ] Rate limiting avec `rack-attack`
- [ ] Logs structurés JSON (production)
- [ ] Migration PostgreSQL
- [ ] Configuration Nginx + SSL

### v2.0 — Fonctionnalités avancées
- [ ] Graphiques d'évolution dans le dashboard (Chartkick)
- [ ] Notifications push (Firebase FCM) depuis l'admin
- [ ] Export CSV des utilisateurs et paiements
- [ ] Multi-admin avec rôles (`superadmin`, `support`, `finance`)
- [ ] Cache `AppConfig` (Redis TTL 5 min)
- [ ] Révocation tokens JWT
- [ ] Factures PDF automatiques après paiement
- [ ] Emails transactionnels (confirmation inscription, reçu paiement)

---

## Annexes

### A. Codes d'erreur API

| Code HTTP | Signification |
|---|---|
| `200` | Succès |
| `201` | Créé avec succès |
| `400` | Requête malformée |
| `401` | Token manquant ou invalide |
| `403` | Accès interdit (compte suspendu) |
| `404` | Ressource introuvable |
| `422` | Données invalides (validation) |
| `429` | Quota journalier dépassé |
| `500` | Erreur serveur interne |

### B. Contacts

| Rôle | Contact |
|---|---|
| Support OpenRouter | https://openrouter.ai/docs |
| Support CinetPay | https://docs.cinetpay.com |
| Support technique DietVision | support@dietvision.app |

---

*Document généré le 25 avril 2026 — DietVision v2.0*
