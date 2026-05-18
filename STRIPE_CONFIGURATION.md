# Configuration Stripe — DietVision Dashboard

> **Date de rédaction :** Mai 2026  
> **API Stripe utilisée :** 2024-09+  
> **Environnement serveur :** `https://api.diet-vision.com`

---

## Table des matières

1. [Prérequis](#1-prérequis)
2. [Clés API et variables d'environnement](#2-clés-api-et-variables-denvironnement)
3. [Configuration du Webhook Stripe](#3-configuration-du-webhook-stripe)
4. [Créer et synchroniser les Plans](#4-créer-et-synchroniser-les-plans)
5. [Créer et synchroniser les Codes Promo](#5-créer-et-synchroniser-les-codes-promo)
6. [Flux de paiement complet](#6-flux-de-paiement-complet)
7. [Événements Webhook gérés](#7-événements-webhook-gérés)
8. [Tester avec Stripe CLI](#8-tester-avec-stripe-cli)
9. [Tableau de bord Stripe — vérifications utiles](#9-tableau-de-bord-stripe--vérifications-utiles)
10. [Résolution de problèmes fréquents](#10-résolution-de-problèmes-fréquents)

---

## 1. Prérequis

- Compte Stripe actif (mode **Test** pour développement, mode **Live** pour production)
- Accès SSH au serveur (`root@185.182.8.138`)
- Application Rails déployée dans `/var/www/dietvision/`
- Puma en cours d'exécution en mode production

---

## 2. Clés API et variables d'environnement

### 2.1 Récupérer les clés depuis Stripe

1. Connectez-vous sur [dashboard.stripe.com](https://dashboard.stripe.com)
2. Menu → **Développeurs** → **Clés API**
3. Copiez :
   - **Clé publiable** (`pk_live_...` ou `pk_test_...`) → utilisée côté Flutter
   - **Clé secrète** (`sk_live_...` ou `sk_test_...`) → utilisée côté serveur Rails

### 2.2 Configurer sur le serveur Rails

Les clés sont stockées dans la table `app_configs` du dashboard admin.

**Via le dashboard admin** (`https://api.diet-vision.com/admin/configs`) :

| Clé de configuration     | Valeur                           |
|--------------------------|----------------------------------|
| `stripe_secret_key`      | `sk_live_XXXX` (ou `sk_test_XXXX`) |
| `stripe_webhook_secret`  | `whsec_XXXX` (voir section 3)    |
| `stripe_publishable_key` | `pk_live_XXXX` (ou `pk_test_XXXX`) |

**Fallback via variables d'environnement** (si `AppConfig` vide) :

```bash
# Sur le serveur, éditer le fichier d'environnement
nano /var/www/dietvision/.env

# Ajouter :
STRIPE_SECRET_KEY=sk_live_XXXX
STRIPE_WEBHOOK_SECRET=whsec_XXXX
```

L'initializer Rails charge la clé au démarrage :
```ruby
# config/initializers/stripe.rb
Stripe.api_key = ENV["STRIPE_SECRET_KEY"].to_s
```

> **Important :** Redémarrer Puma après toute modification d'environnement.
> ```bash
> kill $(cat /var/www/dietvision/tmp/pids/puma.pid)
> cd /var/www/dietvision && RAILS_ENV=production nohup /root/.rbenv/versions/3.3.6/bin/bundle exec puma -C config/puma.rb > log/puma.log 2>&1 &
> ```

---

## 3. Configuration du Webhook Stripe

Le webhook permet à Stripe de notifier le serveur des événements de paiement (succès, échec, résiliation).

### 3.1 Créer le webhook dans Stripe

1. Dashboard Stripe → **Développeurs** → **Webhooks**
2. Cliquer **+ Ajouter un endpoint**
3. **URL de l'endpoint :**
   ```
   https://api.diet-vision.com/api/v1/payments/webhook
   ```
4. **Version API :** Laisser sur la version la plus récente
5. **Événements à écouter** (cocher tous ces événements) :

   | Événement                           | Description                                    |
   |-------------------------------------|------------------------------------------------|
   | `checkout.session.completed`        | Paiement initial confirmé                      |
   | `invoice.paid`                      | Abonnement activé / renouvelé                  |
   | `invoice.payment_failed`            | Échec de paiement (Stripe retentera)           |
   | `customer.subscription.deleted`     | Abonnement résilié → retour en Free            |
   | `customer.subscription.updated`     | Changement de plan, pause, reprise             |

6. Cliquer **Ajouter un endpoint**

### 3.2 Récupérer le Signing Secret

Après création du webhook :
1. Cliquer sur l'endpoint créé
2. Section **Signing secret** → **Révéler**
3. Copier la valeur `whsec_XXXX`
4. La coller dans `AppConfig.stripe_webhook_secret` (voir section 2.2)

### 3.3 Comment fonctionne la vérification

```ruby
# app/controllers/api/v1/payments_controller.rb
def webhook
  payload   = request.raw_post
  signature = request.env["HTTP_STRIPE_SIGNATURE"]
  
  event = StripeService.new.construct_event(payload, signature)
  # Stripe::SignatureVerificationError levée si signature invalide
  StripeService.new.handle_event(event)
  head :ok
end
```

> **Note :** Le webhook est le seul endpoint qui skip l'authentification JWT (`skip_authentication :webhook`).

---

## 4. Créer et synchroniser les Plans

### 4.1 Créer un plan dans le dashboard admin

1. Aller sur `https://api.diet-vision.com/admin/plans`
2. Cliquer **Nouveau plan**
3. Remplir les champs :

   | Champ               | Description                                  | Exemple           |
   |---------------------|----------------------------------------------|-------------------|
   | Nom                 | Nom affiché dans l'app                       | `Pro`             |
   | Slug                | Identifiant unique (minuscules)              | `pro`             |
   | Description         | Description courte                           | `Accès complet IA`|
   | Prix EUR (centimes) | Prix en centimes (399 = 3,99 €)             | `399`             |
   | Fréquence           | `monthly` / `quarterly` / `yearly`          | `monthly`         |
   | Badge               | Étiquette affichée (`Populaire`, etc.)       | `Populaire`       |
   | Fonctionnalités     | Liste des features incluses                  | voir ci-dessous   |
   | Statut              | `draft` (invisible) ou `active` (visible)   | `draft`           |

4. Cliquer **Créer**

### 4.2 Synchroniser le plan avec Stripe

> Cette étape crée le **Produit** et le **Prix** correspondants dans Stripe.

1. Dans la liste des plans, cliquer **Sync Stripe** sur le plan souhaité
2. Le bouton appelle `POST /admin/plans/:id/sync_stripe`
3. Le serveur crée automatiquement :
   - Un **Stripe Product** (avec métadonnées `plan_id`, `plan_slug`, `app: "dietvision"`)
   - Un **Stripe Price** récurrent dans la bonne devise et fréquence
4. Le `stripe_price_id` est sauvegardé dans la base de données locale

**Ce qui se passe côté Stripe :**
```
Stripe Product créé :
  name: "Pro"
  metadata: { plan_id: 2, plan_slug: "pro", app: "dietvision" }

Stripe Price créé :
  product: prod_XXXX
  unit_amount: 399
  currency: "eur"
  recurring: { interval: "month" }
  metadata: { plan_id: 2, plan_slug: "pro" }
```

> **Attention :** Si vous modifiez le prix d'un plan déjà synchronisé, cliquez à nouveau **Sync Stripe**. L'ancien prix sera archivé et un nouveau sera créé (Stripe ne permet pas de modifier un prix existant).

### 4.3 Activer le plan

Une fois synchronisé avec Stripe :
1. Cliquer **Activer** sur le plan
2. Statut passe à `active` → visible dans l'application mobile

### 4.4 Correspondance des slugs et niveaux d'accès

Le serveur détermine le niveau d'accès (`free` / `starter` / `pro` / `premium`) à partir du slug du plan :

| Slug du plan       | Niveau d'accès assigné |
|--------------------|------------------------|
| `starter`          | `starter`              |
| `pro`              | `pro`                  |
| `premium` ou `premium-annual` | `premium`   |
| Autre              | Fallback : slug de la table `plans` |

---

## 5. Créer et synchroniser les Codes Promo

### 5.1 Créer un code promo dans le dashboard admin

1. Aller sur `https://api.diet-vision.com/admin/promo_codes`
2. Cliquer **Nouveau code promo**
3. Remplir les champs :

   | Champ                  | Description                                      | Exemple         |
   |------------------------|--------------------------------------------------|-----------------|
   | Code                   | Code saisi par l'utilisateur (majuscules)        | `LAUNCH20`      |
   | Type de remise         | `percent` (%) ou `fixed` (montant fixe)          | `percent`       |
   | Valeur de remise       | Pourcentage ou montant en euros                  | `20` (= 20 %)   |
   | Date d'expiration      | Optionnel                                        | `2026-12-31`    |
   | Utilisations max total | Optionnel (laisser vide = illimité)              | `100`           |
   | Utilisations par user  | Recommandé : `1`                                | `1`             |
   | Plans applicables      | Plans auxquels le code s'applique                | `pro`, `premium`|
   | Statut                 | `active` / `disabled`                           | `active`        |

4. Cliquer **Créer**

### 5.2 Synchronisation automatique avec Stripe

**La synchronisation est automatique** à la création et à chaque mise à jour.

Le serveur crée dans Stripe :
1. Un **Coupon Stripe** (contient la logique de réduction)
2. Un **PromotionCode Stripe** (contient le code visible par l'utilisateur)

```
Stripe Coupon créé :
  name: "LAUNCH20"
  percent_off: 20.0
  duration: "once"
  metadata: { promo_code_id: 5, app: "dietvision" }

Stripe PromotionCode créé :
  coupon: coupon_XXXX
  code: "LAUNCH20"
  max_redemptions: 100
  expires_at: 1767225600
```

### 5.3 Désactiver / Supprimer un code promo

- **Désactiver** : désactive le PromotionCode dans Stripe (code ne fonctionne plus sur la page Checkout)
- **Supprimer** : supprime aussi le Coupon dans Stripe

### 5.4 Génération en masse

Pour générer des codes de type campagne :
1. Cliquer **Générer des codes en masse**
2. Remplir : préfixe, nombre, type et valeur de remise, expiration

> **Note :** Les codes générés en masse ne sont **pas** synchronisés automatiquement avec Stripe. Ils doivent être synchronisés manuellement ou via script si nécessaire.

---

## 6. Flux de paiement complet

```
[App mobile Flutter]
    │
    │  POST /api/v1/payments/subscribe { plan_id: 3 }
    ▼
[Rails Server]
    │  Crée Subscription (status: "pending")
    │  Crée Payment (status: "pending")
    │  StripeService.create_checkout_session(user, plan)
    ▼
[Stripe Checkout]
    │  Utilisateur paie sur stripe.com
    │  (code promo activé si allow_promotion_codes: true)
    ▼
[Stripe Webhook] POST /api/v1/payments/webhook
    │
    ├── checkout.session.completed
    │     → Lie stripe_subscription_id à la Subscription locale
    │
    └── invoice.paid
          → Subscription.status = "active"
          → User.plan = "pro" (selon slug)
          → User.subscription_expires_at = current_period_end
          → Payment.status = "success"
          → Email de confirmation envoyé
    │
    ▼
[App mobile]
    Polling GET /api/v1/user/me → plan mis à jour
    CoachScreen affiche les fonctionnalités premium
```

### 6.1 URLs de retour Stripe

| Événement        | URL                                                                  |
|------------------|----------------------------------------------------------------------|
| Paiement réussi  | `https://api.diet-vision.com/payment/success?session_id={CHECKOUT_SESSION_ID}` |
| Paiement annulé  | `https://api.diet-vision.com/payment/cancel`                        |

---

## 7. Événements Webhook gérés

### `checkout.session.completed`
- Trouve l'abonnement local en `pending` de l'utilisateur
- Sauvegarde le `stripe_subscription_id`
- *(L'activation réelle se fait dans `invoice.paid`)*

### `invoice.paid`
- Récupère `current_period_end` depuis `items.data[0]` (API 2024-09+)
- Active l'abonnement : `status → "active"`
- Met à jour `User.plan` avec le bon niveau (`starter` / `pro` / `premium`)
- Met à jour `User.subscription_expires_at`
- Enregistre le paiement (idempotent sur `payment_intent`)
- Envoie un email de confirmation

### `invoice.payment_failed`
- Passe l'abonnement en `past_due` (accès conservé le temps des relances)
- Envoie un email d'alerte à l'utilisateur
- Stripe retentera automatiquement (Smart Retries)

### `customer.subscription.deleted`
- Passe l'abonnement en `cancelled`
- Remet l'utilisateur en `plan: "free"`
- Supprime `subscription_expires_at`

### `customer.subscription.updated`
- Synchronise `expires_at` et le statut de l'abonnement local

---

## 8. Tester avec Stripe CLI

### 8.1 Installation

```bash
# macOS
brew install stripe/stripe-cli/stripe

# Windows
scoop install stripe
```

### 8.2 Se connecter et rediriger les webhooks

```bash
stripe login
stripe listen --forward-to https://api.diet-vision.com/api/v1/payments/webhook
```

En développement local :
```bash
stripe listen --forward-to http://localhost:3000/api/v1/payments/webhook
```

### 8.3 Cartes de test Stripe

| Carte                  | Numéro               | Résultat         |
|------------------------|----------------------|------------------|
| Visa (succès)          | `4242 4242 4242 4242` | Paiement réussi  |
| Visa (3D Secure)       | `4000 0027 6000 3184` | Authentification |
| Paiement refusé        | `4000 0000 0000 0002` | Carte refusée    |
| Fonds insuffisants     | `4000 0000 0000 9995` | Échec paiement   |

- **Date d'expiration :** N'importe quelle date future (ex: `12/29`)
- **CVC :** N'importe quel 3 chiffres (ex: `123`)
- **Code postal :** N'importe quoi (ex: `75001`)

### 8.4 Déclencher des événements manuellement

```bash
# Simuler un paiement réussi
stripe trigger invoice.paid

# Simuler une résiliation
stripe trigger customer.subscription.deleted

# Simuler un échec de paiement
stripe trigger invoice.payment_failed
```

---

## 9. Tableau de bord Stripe — vérifications utiles

### Vérifier qu'un abonnement est actif

1. Dashboard Stripe → **Clients**
2. Chercher par email utilisateur
3. Onglet **Abonnements** → vérifier `Actif`

### Vérifier les logs webhook

1. Dashboard Stripe → **Développeurs** → **Webhooks**
2. Cliquer sur l'endpoint
3. Onglet **Tentatives récentes** → voir les réponses 200/400/500

### Vérifier un coupon promo

1. Dashboard Stripe → **Produits** → **Coupons**
2. Vérifier que le coupon avec le bon nom existe et est actif

---

## 10. Résolution de problèmes fréquents

### ❌ "Plan sans Stripe Price ID"

**Cause :** Le plan n'a pas encore été synchronisé avec Stripe.  
**Solution :** Aller dans `/admin/plans` et cliquer **Sync Stripe** sur le plan concerné.

---

### ❌ Le code promo est "invalide" sur la page Stripe Checkout

**Causes possibles :**
1. Le code n'a pas été synchronisé avec Stripe (créé avant l'implémentation auto-sync)
2. Le PromotionCode Stripe est inactif

**Solution :**
- Aller dans `/admin/promo_codes`, ouvrir le code, cliquer **Modifier** puis **Sauvegarder** (force une re-synchronisation)
- Vérifier dans Stripe Dashboard → **Produits** → **Codes promo** que le code existe

---

### ❌ L'abonnement reste en "pending" après paiement

**Cause :** Le webhook Stripe n'a pas été reçu ou traité.  
**Vérification :**
```bash
# Sur le serveur
tail -100 /var/www/dietvision/log/production.log | grep -i stripe
```

**Solutions :**
1. Vérifier que le webhook est configuré dans Stripe (section 3.1)
2. Vérifier que `stripe_webhook_secret` est bien configuré
3. En dernier recours, activer manuellement via SQLite :
```bash
sqlite3 /var/www/dietvision/storage/production.sqlite3
UPDATE subscriptions SET status='active', expires_at=datetime('now','+30 days') WHERE user_id=X AND status='pending';
UPDATE users SET plan='pro', subscription_expires_at=datetime('now','+30 days') WHERE id=X;
.quit
```

---

### ❌ `current_period_end` absent / erreur NoMethodError

**Cause :** API Stripe 2024-09+ a déplacé `current_period_end` dans `items.data[0]`.  
**Solution :** Le code utilise déjà un helper compatible :
```ruby
def period_end(stripe_sub)
  stripe_sub.respond_to?(:current_period_end) && stripe_sub.current_period_end.present? \
    ? stripe_sub.current_period_end \
    : stripe_sub.items.data.first.current_period_end
end
```
Si l'erreur persiste, vérifier la version de la gem Stripe dans `Gemfile.lock`.

---

### ❌ "Stripe webhook signature error"

**Cause :** Le `stripe_webhook_secret` (`whsec_...`) ne correspond pas à l'endpoint Stripe.  
**Solution :**
1. Dashboard Stripe → **Développeurs** → **Webhooks** → cliquer sur l'endpoint
2. **Signing secret** → **Révéler**
3. Mettre à jour `AppConfig.stripe_webhook_secret` dans `/admin/configs`
4. Redémarrer Puma

---

### ❌ L'utilisateur a `plan: "premium"` mais s'est abonné en "pro"

**Cause :** Ancien bug — `plan_level_from_subscription` retournait `"premium"` par défaut.  
**Vérification :**
```bash
sqlite3 /var/www/dietvision/storage/production.sqlite3
SELECT u.email, u.plan, s.plan, s.status FROM users u JOIN subscriptions s ON s.user_id = u.id WHERE s.status='active';
```
**Correction manuelle si nécessaire :**
```sql
UPDATE users SET plan='pro' WHERE id=X;
```

---

## Récapitulatif des URLs importantes

| Service                    | URL                                                        |
|----------------------------|------------------------------------------------------------|
| Dashboard admin            | `https://api.diet-vision.com/admin`                       |
| Webhook endpoint           | `https://api.diet-vision.com/api/v1/payments/webhook`     |
| Page succès paiement       | `https://api.diet-vision.com/payment/success`             |
| Page annulation paiement   | `https://api.diet-vision.com/payment/cancel`              |
| Dashboard Stripe           | `https://dashboard.stripe.com`                            |
| Stripe CLI docs            | `https://stripe.com/docs/stripe-cli`                      |
