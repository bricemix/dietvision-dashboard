# Emails & Gestion de Compte — DietVision

> **Stack :** Rails 8 · ActionMailer · Resend SMTP · JWT (HS256) · SQLite  
> **Serveur :** `https://api.diet-vision.com`  
> **Date :** Mai 2026

---

## Table des matières

1. [Infrastructure email (Resend SMTP)](#1-infrastructure-email-resend-smtp)
2. [Mailers — vue d'ensemble](#2-mailers--vue-densemble)
3. [UserMailer — emails transactionnels](#3-usermailer--emails-transactionnels)
4. [PremiumMailer — bilan hebdomadaire](#4-premiummailer--bilan-hebdomadaire)
5. [Templates HTML des emails](#5-templates-html-des-emails)
6. [Gestion de compte — API mobile](#6-gestion-de-compte--api-mobile)
7. [Authentification JWT et sessions](#7-authentification-jwt-et-sessions)
8. [Modèle User — champs et méthodes](#8-modèle-user--champs-et-méthodes)
9. [Gestion profil — endpoints API](#9-gestion-profil--endpoints-api)
10. [Gestion admin des comptes](#10-gestion-admin-des-comptes)
11. [Tester les emails en local](#11-tester-les-emails-en-local)
12. [Résolution de problèmes fréquents](#12-résolution-de-problèmes-fréquents)

---

## 1. Infrastructure email (Resend SMTP)

### Fournisseur : Resend

Les emails sont envoyés via **[Resend](https://resend.com)** en SMTP sur le port **465 (SSL)**.

| Paramètre        | Valeur                         |
|------------------|-------------------------------|
| Serveur SMTP     | `smtp.resend.com`             |
| Port             | `465` (SSL)                   |
| Utilisateur      | `resend` (fixe)               |
| Mot de passe     | `RESEND_API_KEY` (variable env) |
| Expéditeur       | `DietVision <noreply@diet-vision.com>` |
| Domaine vérifié  | `diet-vision.com`             |

### Configuration Rails (`config/environments/production.rb`)

```ruby
config.action_mailer.delivery_method       = :smtp
config.action_mailer.raise_delivery_errors = false   # ne bloque pas l'app en cas d'erreur SMTP
config.action_mailer.perform_deliveries    = true
config.action_mailer.default_url_options   = { host: "diet-vision.com", protocol: "https" }

config.action_mailer.smtp_settings = {
  address:              "smtp.resend.com",
  port:                 465,
  ssl:                  true,
  user_name:            "resend",
  password:             ENV.fetch("RESEND_API_KEY", ""),
  authentication:       :plain,
  enable_starttls_auto: false
}
```

### Configurer la clé API Resend sur le serveur

**Via le dashboard admin** (`/admin/configs`) → clé `resend_api_key`

Ou directement via variable d'environnement sur le serveur :
```bash
# Ajouter dans /var/www/dietvision/.env
RESEND_API_KEY=re_XXXXXXXXXXXX
```

### Obtenir une clé Resend

1. Créer un compte sur [resend.com](https://resend.com)
2. **Domains** → Ajouter `diet-vision.com` → Vérifier via DNS (enregistrements TXT/MX)
3. **API Keys** → Créer une clé → Copier `re_XXXXXXXXXX`
4. La coller dans la config serveur

---

## 2. Mailers — vue d'ensemble

```
app/mailers/
├── application_mailer.rb        ← Mailer de base (from, layout)
├── user_mailer.rb               ← Emails transactionnels (inscription, paiement)
└── premium_mailer.rb            ← Bilan hebdomadaire Premium
```

### `application_mailer.rb`

```ruby
class ApplicationMailer < ActionMailer::Base
  default from: "DietVision <noreply@diet-vision.com>"
  layout "mailer"
end
```

Tous les mailers héritent de `ApplicationMailer`. Le layout `mailer` est défini dans :
- `app/views/layouts/mailer.html.erb` — version HTML
- `app/views/layouts/mailer.text.erb` — version texte brut

### Récapitulatif des emails envoyés

| Email                     | Mailer               | Méthode                   | Déclencheur                              |
|---------------------------|----------------------|---------------------------|------------------------------------------|
| Bienvenue                 | `UserMailer`         | `welcome(user)`           | `POST /api/v1/auth/register`             |
| Paiement échoué           | `UserMailer`         | `payment_failed(user)`    | Webhook Stripe `invoice.payment_failed`  |
| Abonnement activé         | `UserMailer`         | `subscription_activated(user, expires_at)` | Webhook Stripe `invoice.paid` |
| Bilan hebdomadaire Premium| `PremiumMailer`      | `weekly_digest(user)`     | Tâche planifiée (chaque lundi matin)     |

---

## 3. UserMailer — emails transactionnels

**Fichier :** `app/mailers/user_mailer.rb`

### 3.1 Email de bienvenue — `welcome(user)`

**Quand :** Immédiatement après l'inscription réussie (`deliver_now`)  
**Sujet :** `Bienvenue sur DietVision 🥗`

```ruby
# Déclenché dans AuthController#register
UserMailer.welcome(user).deliver_now
```

**Contenu de l'email :**
- Salutation personnalisée avec le prénom
- Présentation des 3 fonctionnalités clés (analyse photo, coach IA, statistiques)
- Badge indiquant le quota journalier gratuit (`AppConfig.free_daily_limit`)
- Bouton CTA → `https://diet-vision.com`
- Adresse support : `support@diet-vision.com`

**Variables disponibles dans le template :**

| Variable    | Type        | Description                     |
|-------------|-------------|---------------------------------|
| `@user`     | `User`      | L'utilisateur qui vient de s'inscrire |

---

### 3.2 Paiement échoué — `payment_failed(user)`

**Quand :** Webhook Stripe `invoice.payment_failed` (renouvellement refusé)  
**Sujet :** `⚠️ Problème de paiement — DietVision Premium`

```ruby
# Déclenché dans StripeService#handle_invoice_payment_failed
UserMailer.payment_failed(user).deliver_later rescue nil
```

**Contenu de l'email :**
- Alerte rouge : "Paiement échoué"
- Rassurance : l'accès Premium est maintenu le temps des relances Stripe
- 3 étapes : vérifier la carte / mettre à jour / contacter la banque
- Bouton CTA → "Mettre à jour ma carte"
- Note : "Stripe va automatiquement retenter le prélèvement"

> **Important :** L'abonnement passe en `past_due` (pas `cancelled`). L'accès Premium est conservé pendant les relances automatiques de Stripe (Smart Retries : J+1, J+3, J+7).

**Variables disponibles dans le template :**

| Variable | Type   | Description              |
|----------|--------|--------------------------|
| `@user`  | `User` | L'utilisateur concerné   |

---

### 3.3 Abonnement activé — `subscription_activated(user, expires_at)`

**Quand :** Webhook Stripe `invoice.paid` (première activation et chaque renouvellement)  
**Sujet :** `✅ Votre abonnement Premium est actif — DietVision`

```ruby
# Déclenché dans StripeService#handle_invoice_paid
UserMailer.subscription_activated(user, expires_at).deliver_later rescue nil
```

**Contenu de l'email :**
- Félicitations + encadré vert "Premium activé avec succès"
- Date d'expiration affichée (`Valable jusqu'au jj/mm/aaaa`)
- 4 avantages Premium : analyses illimitées, coach IA avancé, historique complet, renouvellement auto
- Bouton CTA → "Accéder à Premium"

**Variables disponibles dans le template :**

| Variable      | Type       | Description                     |
|---------------|------------|---------------------------------|
| `@user`       | `User`     | L'utilisateur abonné            |
| `@expires_at` | `DateTime` | Date de fin d'abonnement (UTC)  |

---

## 4. PremiumMailer — bilan hebdomadaire

**Fichier :** `app/mailers/premium_mailer.rb`

### `weekly_digest(user)`

**Quand :** Chaque lundi matin (tâche planifiée à configurer via cron)  
**Sujet :** `Votre bilan DietVision — semaine du {date}`  
**Destinataires :** Utilisateurs avec plan `premium` uniquement

```ruby
PremiumMailer.weekly_digest(user).deliver_later
```

**Données calculées dans le mailer :**

| Variable          | Description                                         |
|-------------------|-----------------------------------------------------|
| `@analyses_count` | Nombre d'analyses photo la semaine écoulée          |
| `@coach_count`    | Nombre de messages coach la semaine écoulée         |
| `@total_calls`    | Total appels API la semaine                         |
| `@analyses_month` | Analyses photo depuis le début du mois              |
| `@expires_at`     | Date d'expiration de l'abonnement                   |
| `@days_remaining` | Jours restants avant expiration                     |
| `@expiry_warning` | `true` si expiration dans ≤ 7 jours                |
| `@week_label`     | Libellé "1 mai – 7 mai 2026"                       |
| `@activity_level` | `inactive` / `low` / `medium` / `high`              |

**Logique niveau d'activité :**

| Analyses photo | Niveau    | Message                         |
|----------------|-----------|---------------------------------|
| 0              | `inactive`| Relance douce                   |
| 1–3            | `low`     | "Bon début"                     |
| 4–10           | `medium`  | "Sur la bonne voie"             |
| > 10           | `high`    | "Impressionnant !"              |

**Contenu de l'email :**
- Grille de stats 3 colonnes : analyses / messages coach / analyses du mois
- Barre d'activité visuelle (0 % → 95 %)
- Alerte expiration si `@expiry_warning == true`
- Récapitulatif compte (plan, quota, date expiration)
- Conseil de la semaine (rotation cyclique parmi 6 conseils)
- Bouton CTA → "Ouvrir DietVision"

### Planification du bilan hebdomadaire

Ajouter une tâche cron sur le serveur (exemple avec `whenever` gem ou cron système) :

```bash
# Crontab (lundi à 8h00)
0 8 * * 1 cd /var/www/dietvision && RAILS_ENV=production /root/.rbenv/versions/3.3.6/bin/bundle exec rails runner "User.where(plan: 'premium').find_each { |u| PremiumMailer.weekly_digest(u).deliver_later rescue nil }"
```

---

## 5. Templates HTML des emails

### Structure commune de tous les emails

```
┌──────────────────────────────────┐
│  HEADER  (fond noir #0a0a0f)    │
│  Logo Diet + Vision (vert lime) │
│  Tagline grise                  │
├──────────────────────────────────┤
│  BODY    (fond blanc)           │
│  Contenu spécifique à l'email   │
│  Bouton CTA (fond #c8ff00)      │
├──────────────────────────────────┤
│  FOOTER  (fond #f8f8fc)         │
│  © 2026 DietVision              │
└──────────────────────────────────┘
```

### Charte graphique des emails

| Élément           | Valeur          |
|-------------------|-----------------|
| Fond header       | `#0a0a0f`       |
| Texte "Diet"      | `#ffffff`       |
| Texte "Vision"    | `#c8ff00` (vert lime) |
| Fond CTA button   | `#c8ff00`       |
| Texte CTA         | `#0a0a0f`       |
| Police            | Helvetica Neue / Arial |
| Largeur max       | `560px` / `580px` |
| Border-radius     | `16px`          |

### Fichiers des templates

```
app/views/
├── layouts/
│   ├── mailer.html.erb              ← Layout HTML de base (yield)
│   └── mailer.text.erb              ← Layout texte brut
├── user_mailer/
│   ├── welcome.html.erb             ← Bienvenue (HTML)
│   ├── welcome.text.erb             ← Bienvenue (texte)
│   ├── subscription_activated.html.erb  ← Premium activé (HTML)
│   └── payment_failed.html.erb      ← Paiement échoué (HTML)
└── premium_mailer/
    ├── weekly_digest.html.erb       ← Bilan hebdo (HTML)
    └── weekly_digest.text.erb       ← Bilan hebdo (texte)
```

> **Note :** Les emails HTML sont **auto-contenus** (styles inline) pour assurer la compatibilité avec tous les clients email (Gmail, Outlook, Apple Mail…).

---

## 6. Gestion de compte — API mobile

### Routes disponibles

**Base URL :** `https://api.diet-vision.com/api/v1`

| Méthode | Endpoint              | Auth | Action                          |
|---------|-----------------------|------|---------------------------------|
| `POST`  | `/auth/register`      | ❌   | Créer un compte                 |
| `POST`  | `/auth/login`         | ❌   | Se connecter                    |
| `DELETE`| `/auth/logout`        | ✅   | Se déconnecter                  |
| `GET`   | `/auth/me`            | ✅   | Infos utilisateur courant       |
| `POST`  | `/auth/refresh`       | ✅   | Renouveler le token JWT         |
| `GET`   | `/profile`            | ✅   | Voir le profil complet          |
| `PATCH` | `/profile`            | ✅   | Modifier nom/téléphone/pays/mdp |
| `GET`   | `/profile/usage`      | ✅   | Quota API utilisé aujourd'hui   |

### `POST /auth/register`

```json
// Body
{
  "name": "Marie Dupont",
  "email": "marie@example.com",
  "password": "MonMotDePasse123",
  "phone": "+33612345678",
  "country": "FR"
}

// Réponse 201
{
  "token": "eyJhbGci...",
  "user": {
    "id": 42,
    "name": "Marie Dupont",
    "email": "marie@example.com",
    "plan": "free",
    "premium": false
  }
}
```

**Effets :** Crée le compte → envoie l'email de bienvenue → génère un JWT

---

### `POST /auth/login`

```json
// Body
{
  "email": "marie@example.com",
  "password": "MonMotDePasse123"
}

// Réponse 200
{
  "token": "eyJhbGci...",
  "user": {
    "id": 42,
    "name": "Marie Dupont",
    "email": "marie@example.com",
    "plan": "premium",
    "subscription_plan": "premium",
    "subscription_expires_at": "2026-06-14T08:00:00Z",
    "premium": true
  }
}
```

**Erreurs possibles :**

| Code | Message                          | Cause                       |
|------|----------------------------------|-----------------------------|
| 401  | Email ou mot de passe incorrect  | Mauvais identifiants        |
| 403  | Compte suspendu                  | `status = "suspended"`      |

---

### `DELETE /auth/logout`

```
Authorization: Bearer eyJhbGci...
```

**Effet :** Efface le `session_token` en base → invalide le JWT sur tous les appareils

```json
// Réponse 200
{ "message": "Déconnecté avec succès" }
```

---

### `GET /auth/me`

Retourne les informations de l'utilisateur courant (identique à la réponse login).

---

### `POST /auth/refresh`

Génère un nouveau token JWT avec un nouveau `session_token` → invalide automatiquement les sessions ouvertes sur d'autres appareils.

```json
// Réponse 200
{ "token": "eyJhbGci..." }
```

---

### `PATCH /profile`

```json
// Body (tous les champs sont optionnels)
{
  "user": {
    "name": "Marie Martin",
    "phone": "+33698765432",
    "country": "BE",
    "password": "NouveauMotDePasse456"
  }
}

// Réponse 200 — profil mis à jour
{
  "id": 42,
  "name": "Marie Martin",
  "email": "marie@example.com",
  "plan": "premium",
  "premium": true,
  "subscription_expires_at": "2026-06-14T08:00:00Z",
  "api_calls_today": 3,
  "daily_limit": 50
}
```

---

### `GET /profile/usage`

```json
// Réponse 200
{
  "today": 3,
  "this_month": 47,
  "daily_limit": 10,
  "premium": false,
  "subscription_expires_at": null
}
```

---

## 7. Authentification JWT et sessions

**Fichier :** `app/controllers/concerns/jwt_authenticatable.rb`

### Fonctionnement du JWT

| Paramètre   | Valeur                              |
|-------------|-------------------------------------|
| Algorithme  | HS256                               |
| Durée de vie| 30 jours                            |
| Clé secrète | `Rails.application.secret_key_base` |
| Header HTTP | `Authorization: Bearer <token>`     |

### Payload du token

```json
{
  "user_id": 42,
  "session_token": "550e8400-e29b-41d4-a716-446655440000",
  "exp": 1755158400,
  "iat": 1752566400
}
```

### Système de session unique (un seul appareil)

À chaque login ou register, un **UUID `session_token`** est généré et sauvegardé en base :

```ruby
def issue_token(user)
  session_token = SecureRandom.uuid
  user.update_column(:session_token, session_token)
  JwtAuthenticatable.encode(user_id: user.id, session_token: session_token)
end
```

**Vérification à chaque requête authentifiée :**

```ruby
# Si l'utilisateur s'est reconnecté sur un autre appareil,
# le session_token en base ne correspond plus → 401
if @current_user.session_token.present? &&
    payload[:session_token] != @current_user.session_token
  return render json: {
    error: "Votre compte a été connecté sur un autre appareil.",
    code:  "SESSION_INVALIDATED"
  }, status: :unauthorized
end
```

**Dans l'app Flutter**, ce code `SESSION_INVALIDATED` déclenche une déconnexion automatique et affiche une alerte.

### Vérifications effectuées à chaque requête

1. ✅ Token présent dans le header `Authorization`
2. ✅ Token non expiré (< 30 jours)
3. ✅ `user_id` correspond à un utilisateur existant
4. ✅ Compte non suspendu (`status != "suspended"`)
5. ✅ `session_token` du JWT correspond à celui en base

### Endpoints publics (sans authentification)

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/plans`
- `POST /api/v1/payments/webhook`
- `POST /api/v1/promo_codes/validate`

---

## 8. Modèle User — champs et méthodes

**Fichier :** `app/models/user.rb`

### Champs de la base de données

| Colonne                  | Type       | Description                              |
|--------------------------|------------|------------------------------------------|
| `id`                     | Integer    | Identifiant unique                       |
| `name`                   | String     | Prénom + nom                             |
| `email`                  | String     | Email unique (normalisé en minuscules)   |
| `password_digest`        | String     | Mot de passe bcrypt (`has_secure_password`) |
| `phone`                  | String     | Téléphone (facultatif)                   |
| `country`                | String     | Code pays ISO (ex: `FR`, `MG`)           |
| `plan`                   | String     | `free` / `starter` / `pro` / `premium`  |
| `status`                 | String     | `active` / `suspended`                   |
| `stripe_customer_id`     | String     | ID client Stripe (`cus_XXX`)            |
| `subscription_expires_at`| DateTime   | Date de fin d'abonnement                 |
| `trial_ends_at`          | DateTime   | Date de fin de période d'essai           |
| `had_trial`              | Boolean    | A déjà utilisé un essai gratuit          |
| `session_token`          | String     | UUID pour session unique (index unique)  |
| `fitai_profile`          | Text       | Profil nutritionnel JSON                 |
| `body_entries_data`      | Text       | Mesures corporelles JSON                 |
| `planning_data`          | Text       | Planning hebdomadaire JSON               |
| `created_at`             | DateTime   |                                          |
| `updated_at`             | DateTime   |                                          |

### Méthodes importantes

```ruby
user.premium?
# => true si plan == "premium" ET subscription_expires_at dans le futur

user.in_trial?
# => true si trial_ends_at est dans le futur

user.trial_days_remaining
# => nombre de jours restants dans la période d'essai (Integer)

user.start_trial!(days)
# Démarre une période d'essai de X jours
# Passe plan à "free", had_trial à true

user.active_subscription
# => la Subscription active la plus récente (ou nil)

user.total_spent
# => somme de tous les paiements réussis (en centimes)

user.api_calls_this_month
# => nombre d'appels API ce mois
```

### Validations

```ruby
validates :email, presence: true, uniqueness: { case_sensitive: false },
                  format: { with: URI::MailTo::EMAIL_REGEXP }
validates :name, presence: true
# phone est facultatif
```

### Scopes disponibles

```ruby
User.in_trial          # utilisateurs avec essai en cours
User.trial_expired     # utilisateurs dont l'essai est expiré
User.active_users      # status == "active"
User.new_this_month    # inscrits ce mois
```

---

## 9. Gestion profil — endpoints API

### Données nutritionnelles (FitAI)

**`GET /api/v1/user/fitai`** — Récupérer le profil nutritionnel

**`PUT /api/v1/user/fitai`** (alias : `PUT /api/v1/user/profile`) — Sauvegarder

```json
// Body — profil nutritionnel Flutter
{
  "fitai_profile": {
    "age": 28,
    "gender": "female",
    "height": 165,
    "weight": 62,
    "goal": "lose_weight",
    "activityLevel": "moderate"
  }
}
```

### Mesures corporelles

**`GET /api/v1/user/body_entries`** — Récupérer les mesures

**`PUT /api/v1/user/body_entries`** — Sauvegarder

```json
// Body
{
  "body_entries": [
    { "date": "2026-05-01", "weight": 62.5, "bmi": 22.9 },
    { "date": "2026-05-08", "weight": 62.0, "bmi": 22.8 }
  ]
}
```

### Planning hebdomadaire

**`GET /api/v1/user/planning`** — Récupérer le planning

**`PUT /api/v1/user/planning`** — Sauvegarder

```json
// Body
{
  "planning": [
    { "day": "monday", "meals": [...], "calories": 1800 },
    { "day": "tuesday", "meals": [...], "calories": 1750 }
  ]
}
```

---

## 10. Gestion admin des comptes

**URL :** `https://api.diet-vision.com/admin/users`

### Actions disponibles sur un compte utilisateur

| Action             | Route                                   | Effet                                          |
|--------------------|-----------------------------------------|------------------------------------------------|
| Voir le profil     | `GET /admin/users/:id`                  | Détails compte, abonnements, paiements, API    |
| Suspendre          | `POST /admin/users/:id/suspend`         | `status → "suspended"` → login bloqué         |
| Réactiver          | `POST /admin/users/:id/activate`        | `status → "active"`                           |
| Prolonger accès    | `POST /admin/users/:id/extend_subscription` | Ajoute X jours à `subscription_expires_at`|
| Offrir accès       | `POST /admin/users/:id/gift_access`     | Crée un accès gratuit de X jours               |

### Fiche utilisateur dans le dashboard

La page `show` affiche :
- **Informations** : nom, email, téléphone, pays, inscription
- **Abonnement** : plan actuel, date expiration, statut
- **Abonnements** : historique des subscriptions
- **Paiements** : historique des transactions
- **Derniers appels API** : endpoint, modèle, tokens, coût, statut (+ bouton "Voir" si erreur)

### Suspension d'un compte

Un compte suspendu ne peut plus se connecter :

```ruby
# AuthController#login
if user.status == "suspended"
  return render json: { error: "Compte suspendu" }, status: :forbidden
end

# JwtAuthenticatable#authenticate_user!
return render_unauthorized("Compte suspendu") if @current_user.status == "suspended"
```

---

## 11. Tester les emails en local

### Option 1 — Letter Opener (recommandé en dev)

Ajouter dans `Gemfile` :
```ruby
gem "letter_opener", group: :development
```

Dans `config/environments/development.rb` :
```ruby
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
```

Les emails s'ouvrent automatiquement dans le navigateur.

### Option 2 — Console Rails

```ruby
# Sur le serveur
cd /var/www/dietvision
RAILS_ENV=production /root/.rbenv/versions/3.3.6/bin/bundle exec rails console

# Envoyer un email de test
user = User.find_by(email: "test@example.com")
UserMailer.welcome(user).deliver_now
UserMailer.subscription_activated(user, 30.days.from_now).deliver_now
PremiumMailer.weekly_digest(user).deliver_now
```

### Option 3 — Via Python SSH (déploiement/test rapide)

```python
import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("185.182.8.138", username="root", password="2Jefferson2")

cmd = (
    'cd /var/www/dietvision && '
    'RAILS_ENV=production /root/.rbenv/versions/3.3.6/bin/bundle exec rails runner '
    '"UserMailer.welcome(User.first).deliver_now; puts \'OK\'"'
)
stdin, stdout, stderr = ssh.exec_command(cmd, timeout=30)
print(stdout.read().decode())
ssh.close()
```

### Vérifier les logs d'envoi

```bash
# Sur le serveur
tail -f /var/www/dietvision/log/production.log | grep -i "mail\|smtp\|deliver"
```

---

## 12. Résolution de problèmes fréquents

### ❌ Email de bienvenue non reçu

**Vérifications :**
1. Vérifier que `RESEND_API_KEY` est configurée dans `AppConfig` ou `.env`
2. Vérifier les logs Rails : `tail -100 /var/www/dietvision/log/production.log | grep -i mail`
3. Vérifier que le domaine `diet-vision.com` est validé dans Resend Dashboard
4. Vérifier les dossiers spam de l'utilisateur

**Test rapide depuis le serveur :**
```bash
cd /var/www/dietvision && RAILS_ENV=production \
/root/.rbenv/versions/3.3.6/bin/bundle exec rails runner \
"UserMailer.welcome(User.last).deliver_now; puts 'Envoyé'"
```

---

### ❌ "Compte suspendu" au login

**Cause :** L'admin a suspendu le compte (`status = "suspended"`).  
**Solution depuis l'admin :** `/admin/users/:id` → Bouton "Réactiver"  
**Solution en base de données :**
```bash
sqlite3 /var/www/dietvision/storage/production.sqlite3
UPDATE users SET status='active' WHERE email='user@example.com';
.quit
```

---

### ❌ "Votre compte a été connecté sur un autre appareil"

**Cause :** L'utilisateur s'est reconnecté sur un deuxième appareil → son `session_token` a changé.  
**Solution :** L'utilisateur doit se reconnecter normalement sur l'appareil concerné.  
**Si le token doit être réinitialisé manuellement :**
```bash
sqlite3 /var/www/dietvision/storage/production.sqlite3
UPDATE users SET session_token=NULL WHERE email='user@example.com';
.quit
```

---

### ❌ Token JWT expiré (> 30 jours)

**Erreur retournée :** `{ "error": "Token expiré" }` avec status `401`  
**Solution :** L'app Flutter doit renvoyer l'utilisateur vers l'écran de login.  
**Pour prolonger sans reconnexion :** appeler `POST /api/v1/auth/refresh` avant expiration.

---

### ❌ Le bilan hebdomadaire n'est pas envoyé

**Vérifier que le cron est actif :**
```bash
crontab -l | grep weekly_digest
```

**Lancer manuellement :**
```bash
cd /var/www/dietvision && RAILS_ENV=production \
/root/.rbenv/versions/3.3.6/bin/bundle exec rails runner \
"User.where(plan: 'premium').find_each { |u| PremiumMailer.weekly_digest(u).deliver_later rescue nil }; puts 'Bilans envoyés'"
```

---

## Récapitulatif des adresses email

| Rôle          | Adresse                          |
|---------------|----------------------------------|
| Expéditeur    | `noreply@diet-vision.com`        |
| Support       | `support@diet-vision.com`        |
| SMTP provider | Resend (`smtp.resend.com:465`)   |
