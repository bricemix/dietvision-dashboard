class StripeService
  def initialize
    @api_key = AppConfig.stripe_secret_key || ENV["STRIPE_SECRET_KEY"]
    # Clé passée par-appel (thread-safe) — évite la race sur Stripe.api_key global.
    @opts = { api_key: @api_key }
    # On positionne aussi la globale pour les appels Stripe directs hors service.
    Stripe.api_key = @api_key
  end

  # ── Customer ─────────────────────────────────────────────────────────────────
  # Crée ou retrouve le Customer Stripe lié à l'utilisateur.
  # La colonne stripe_customer_id est le seul lien fiable entre les deux systèmes.

  def find_or_create_customer(user)
    if user.stripe_customer_id.present?
      Stripe::Customer.retrieve(user.stripe_customer_id, @opts)
    else
      customer = Stripe::Customer.create({
        email:    user.email,
        name:     user.name,
        metadata: { user_id: user.id, app: "dietvision" }
      }, @opts)
      user.update_column(:stripe_customer_id, customer.id)
      customer
    end
  rescue Stripe::InvalidRequestError => e
    # Customer supprimé côté Stripe → on en recrée un
    Rails.logger.warn("Stripe customer #{user.stripe_customer_id} introuvable, recréation : #{e.message}")
    customer = Stripe::Customer.create({
      email:    user.email,
      name:     user.name,
      metadata: { user_id: user.id, app: "dietvision" }
    }, @opts)
    user.update_column(:stripe_customer_id, customer.id)
    customer
  end

  # ── Créer ou mettre à jour un produit + prix Stripe depuis un Plan Rails ─────
  # Appelé depuis l'admin pour éviter d'aller sur dashboard.stripe.com.
  # Si le plan a déjà un stripe_price_id → on archive l'ancien et on en crée un nouveau.
  # Retourne le nouveau stripe_price_id.

  def sync_plan_to_stripe(plan)
    raise ArgumentError, "Prix EUR manquant (price_eur_cents = 0)" if plan.price_eur_cents.to_i == 0

    interval, interval_count = stripe_interval(plan.billing_frequency)

    # 1. Créer ou retrouver le Produit Stripe
    product = if plan.stripe_product_id.present?
      Stripe::Product.retrieve(plan.stripe_product_id, @opts) rescue nil
    end

    if product.nil?
      product = Stripe::Product.create({
        name:        plan.name,
        description: plan.description.presence || plan.name,
        metadata:    { plan_id: plan.id, plan_slug: plan.slug, app: "dietvision" }
      }, @opts)
      plan.update_column(:stripe_product_id, product.id)
    else
      # Mettre à jour le nom si changé
      Stripe::Product.update(product.id, { name: plan.name }, @opts) rescue nil
    end

    # 2. Archiver l'ancien prix si existant (Stripe ne permet pas de modifier un prix)
    if plan.stripe_price_id.present?
      Stripe::Price.update(plan.stripe_price_id, { active: false }, @opts) rescue nil
    end

    # 3. Créer le nouveau prix récurrent
    price_params = {
      product:   product.id,
      unit_amount: plan.price_eur_cents.to_i,
      currency:  "eur",
      recurring: { interval: interval }.tap { |h| h[:interval_count] = interval_count if interval_count > 1 },
      metadata:  { plan_id: plan.id, plan_slug: plan.slug }
    }

    price = Stripe::Price.create(price_params, @opts)
    plan.update_column(:stripe_price_id, price.id)

    Rails.logger.info("Stripe sync : plan #{plan.name} → price #{price.id}")
    price.id
  end

  # ── Synchroniser un code promo vers Stripe ───────────────────────────────────
  # Crée un Coupon + PromotionCode Stripe depuis un PromoCode Rails.
  # Idempotent : si le coupon existe déjà (stripe_coupon_id présent), on ne recrée pas.
  # Retourne le stripe_promotion_code_id.

  def sync_promo_code_to_stripe(promo_code)
    # 1. Créer ou retrouver le Coupon Stripe
    coupon = if promo_code.stripe_coupon_id.present?
      Stripe::Coupon.retrieve(promo_code.stripe_coupon_id, @opts) rescue nil
    end

    if coupon.nil?
      coupon_params = {
        name:     promo_code.code,
        duration: "once",
        metadata: { promo_code_id: promo_code.id, app: "dietvision" }
      }

      if promo_code.discount_type == "percent"
        coupon_params[:percent_off] = promo_code.discount_value.to_f
      else
        # Montant fixe en centimes EUR
        coupon_params[:amount_off] = (promo_code.discount_value.to_f * 100).round
        coupon_params[:currency]   = "eur"
      end

      coupon = Stripe::Coupon.create(coupon_params, @opts)
      promo_code.update_column(:stripe_coupon_id, coupon.id)
    end

    # 2. Créer le PromotionCode Stripe (le code visible par l'utilisateur)
    # Si un code existe déjà côté Stripe, on l'archive et on en recrée un
    if promo_code.stripe_promotion_code_id.present?
      begin
        Stripe::PromotionCode.update(promo_code.stripe_promotion_code_id, { active: false }, @opts)
      rescue Stripe::InvalidRequestError
        nil
      end
    end

    promo_params = {
      coupon: coupon.id,
      code:   promo_code.code,
      metadata: { promo_code_id: promo_code.id }
    }
    promo_params[:max_redemptions] = promo_code.max_uses_total if promo_code.max_uses_total.present?
    promo_params[:expires_at]      = promo_code.expires_at.to_i if promo_code.expires_at.present?

    promotion = Stripe::PromotionCode.create(promo_params, @opts)
    promo_code.update_column(:stripe_promotion_code_id, promotion.id)

    Rails.logger.info("Stripe sync promo : #{promo_code.code} → coupon #{coupon.id} / promo #{promotion.id}")
    promotion.id
  end

  # ── Checkout Session (mode: subscription) ────────────────────────────────────
  # Retourne une URL Stripe Checkout.
  # mode: "subscription" → facturation récurrente gérée à 100% par Stripe.
  # NE PAS utiliser mode: "payment" pour les abonnements.

  def create_checkout_session(user:, plan:, locale: "fr")
    raise ArgumentError, "Plan sans Stripe Price ID" if plan.stripe_price_id.blank?

    customer = find_or_create_customer(user)

    # Normalise la locale app vers une locale Stripe valide.
    # Stripe accepte : fr, en, de, es, pt, it, nl, ja, zh, etc.
    # Notre "us" = anglais → "en". Fallback sur "fr" pour les inconnues.
    stripe_locale = stripe_locale_for(locale)

    session = Stripe::Checkout::Session.create({
      customer:    customer.id,
      line_items:  [{ price: plan.stripe_price_id, quantity: 1 }],
      mode:        "subscription",
      locale:      stripe_locale,
      allow_promotion_codes: true,           # ← Champ "Code promo" sur la page Stripe
      success_url: "https://api.diet-vision.com/payment/success?session_id={CHECKOUT_SESSION_ID}&locale=#{stripe_locale}",
      cancel_url:  "https://api.diet-vision.com/payment/cancel?locale=#{stripe_locale}",
      subscription_data: {
        metadata: { user_id: user.id, plan_id: plan.id, plan_slug: plan.slug }
      },
      metadata: { user_id: user.id, plan_id: plan.id, plan_slug: plan.slug }
    }, @opts)

    { checkout_url: session.url, session_id: session.id }
  end

  # ── Customer Portal ──────────────────────────────────────────────────────────
  # Crée une session Stripe Billing Portal pour que l'utilisateur puisse
  # gérer son abonnement (annuler, changer carte, voir factures).
  # Retourne l'URL du portail à ouvrir dans le navigateur.

  def create_portal_session(customer_id:, return_url:)
    session = Stripe::BillingPortal::Session.create({
      customer:   customer_id,
      return_url: return_url
    }, @opts)
    session.url
  end

  # ── Webhook dispatcher ────────────────────────────────────────────────────────

  def construct_event(payload, signature)
    # Vérifie la signature contre TOUS les secrets disponibles (live + test + ENV).
    # Stripe peut envoyer des événements test (livemode:false) signés avec le
    # secret test ET des événements live signés avec le secret live, parfois sur
    # la même URL d'endpoint. On accepte celui qui matche.
    secrets = [
      AppConfig.get("stripe_webhook_secret"),
      AppConfig.get("stripe_webhook_secret_test"),
      ENV["STRIPE_WEBHOOK_SECRET"]
    ].map { |x| x.to_s.strip }.reject(&:blank?).uniq

    raise Stripe::SignatureVerificationError.new("Aucun webhook secret configuré", signature) if secrets.empty?

    last_error = nil
    secrets.each do |secret|
      begin
        return Stripe::Webhook.construct_event(payload, signature, secret)
      rescue Stripe::SignatureVerificationError => e
        last_error = e
      end
    end
    raise last_error
  end

  def handle_event(event)
    case event.type
    when "checkout.session.completed"    then handle_checkout_completed(event)
    when "invoice.paid"                  then handle_invoice_paid(event)
    when "invoice.payment_failed"        then handle_invoice_payment_failed(event)
    when "customer.subscription.deleted" then handle_subscription_deleted(event)
    when "customer.subscription.updated" then handle_subscription_updated(event)
    else
      Rails.logger.info("Stripe webhook non géré : #{event.type}")
    end
  end

  private

  # ── checkout.session.completed ────────────────────────────────────────────────
  # Stripe vient de créer l'abonnement. On lie stripe_subscription_id à notre
  # Subscription locale (créée en "pending" dans payments_controller).

  def handle_checkout_completed(event)
    session                = event.data.object
    stripe_subscription_id = session.subscription
    user_id                = session.metadata["user_id"]&.to_i

    user = User.find_by(id: user_id)
    return log_warn("checkout.completed : user #{user_id} introuvable") unless user

    # BUG-08 : valider que la session Stripe appartient bien au customer de cet utilisateur.
    # Empêche l'activation frauduleuse si les métadonnées sont altérées.
    if user.stripe_customer_id.present? && session.customer != user.stripe_customer_id
      return log_warn("checkout.completed : customer Stripe #{session.customer} != user #{user.id} (#{user.stripe_customer_id}) — FRAUDE POSSIBLE")
    end

    # BUG-08 : chercher d'abord par provider_ref (session_id) pour éviter les collisions
    # entre plusieurs abonnements pending du même utilisateur.
    subscription = Payment.find_by(provider_ref: session.id)&.subscription ||
                   user.subscriptions.where(status: "pending")
                        .order(created_at: :desc).first
    return log_warn("checkout.completed : aucun abonnement pending pour user #{user_id}") unless subscription

    # Double-vérification que la subscription appartient bien à cet utilisateur
    return log_warn("checkout.completed : subscription #{subscription.id} n'appartient pas à user #{user_id}") unless subscription.user_id == user.id

    # Stocker le stripe_subscription_id → indispensable pour les futurs webhooks
    subscription.update_columns(stripe_subscription_id: stripe_subscription_id) if stripe_subscription_id.present?

    detect_and_record_promo_redemption(session, user)

    Rails.logger.info("Stripe checkout.completed : #{user.email} → sub #{stripe_subscription_id}")
  end

  # ── Détection & enregistrement d'un code promo utilisé ─────────────────────────
  # Stripe applique le code côté hosted checkout (allow_promotion_codes: true) —
  # on ne le sait qu'en relisant la session avec le détail des réductions.
  # Idempotent via l'index unique sur stripe_session_id (webhooks Stripe peuvent être renvoyés).

  def detect_and_record_promo_redemption(session, user)
    return if session.id.blank?
    return if PromoCodeRedemption.exists?(stripe_session_id: session.id)

    full_session = Stripe::Checkout::Session.retrieve(
      { id: session.id, expand: ["total_details.breakdown.discounts"] }, @opts
    )
    discounts = full_session.total_details&.breakdown&.discounts
    return if discounts.blank?

    promo_stripe_id = discounts.first&.discount&.promotion_code
    return if promo_stripe_id.blank?

    promo_code = PromoCode.find_by(stripe_promotion_code_id: promo_stripe_id)
    return unless promo_code

    payment = Payment.find_by(provider_ref: session.id)

    PromoCodeRedemption.create!(
      user: user, promo_code: promo_code, payment: payment, stripe_session_id: session.id
    )
    promo_code.increment_usage!
    Rails.logger.info("Code promo utilisé : #{promo_code.code} par #{user.email}")
  rescue => e
    Rails.logger.error("detect_and_record_promo_redemption error: #{e.message}")
  end

  # ── invoice.paid ──────────────────────────────────────────────────────────────
  # Déclenché à chaque paiement réussi (création ET renouvellement).
  # C'est ici qu'on active ou prolonge l'accès Premium.
  # expires_at est défini par Stripe (current_period_end) — JAMAIS calculé en dur.

  def handle_invoice_paid(event)
    invoice = event.data.object
    # Compatibilité Stripe API 2026-04-22.dahlia : invoice.subscription a été
    # déplacé vers invoice.parent.subscription_details.subscription dans le nouvel objet Invoice.
    stripe_subscription_id = invoice_subscription_id(invoice)
    return unless stripe_subscription_id.present?

    user = User.find_by(stripe_customer_id: invoice.customer)
    return log_warn("invoice.paid : aucun user pour customer #{invoice.customer}") unless user

    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription_id) ||
                   user.subscriptions.where(status: %w[pending active past_due])
                       .order(created_at: :desc).first

    return log_warn("invoice.paid : aucune subscription pour #{stripe_subscription_id}") unless subscription

    # Récupérer la vraie date de fin depuis Stripe (non bloquant si l'API échoue)
    stripe_sub = nil
    expires_at = nil
    begin
      stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id, @opts)
      expires_at = Time.at(period_end(stripe_sub)).utc
    rescue => e
      # Si l'API Stripe échoue (mauvaise clé, réseau) → calculer expires_at localement
      # à partir de la fréquence du plan. Moins précis mais garantit l'activation.
      Rails.logger.warn("[StripeService] Stripe::Subscription.retrieve échoué : #{e.message} — expires_at calculé localement")
      plan_obj   = Plan.find_by(slug: subscription.plan)
      expires_at = Time.current + (plan_obj&.duration || 1.month)
    end

    plan_level = plan_level_from_subscription(subscription)

    # ── ÉTAPE 1 : Activer l'abonnement et le plan utilisateur (transaction critique) ──
    # SÉPARÉ du paiement pour que l'activation ne soit jamais bloquée par
    # une erreur d'enregistrement comptable (validation, contrainte DB…).
    ActiveRecord::Base.transaction do
      # period_start peut lever une exception sur certaines versions de l'API Stripe
      # (current_period_start absent de la racine) → on l'encapsule pour ne pas
      # faire rollback toute la transaction à cause d'une donnée accessoire.
      starts_at = begin
        stripe_sub ? Time.at(period_start(stripe_sub)).utc : Time.current
      rescue => e
        Rails.logger.warn("[StripeService] period_start échoué (#{e.message}) — starts_at = now")
        Time.current
      end

      subscription.update!(
        stripe_subscription_id: stripe_subscription_id,
        status:     "active",
        starts_at:  starts_at,
        expires_at: expires_at
      )
      user.update!(
        plan:                    plan_level,
        subscription_expires_at: expires_at,
        trial_ends_at:           nil   # Souscription active → fin de l'essai Starter
      )
    end

    Rails.logger.info("Stripe invoice.paid : #{user.email} → #{plan_level} jusqu'au #{expires_at.strftime('%d/%m/%Y')}")

    # ── ÉTAPE 2 : Enregistrer le paiement (hors transaction critique) ──
    # Une erreur ici ne doit pas rollback l'activation du plan ci-dessus.
    begin
      # Chercher d'abord le paiement PENDING lié à cet abonnement.
      # Le paiement initial est créé dans #subscribe avec provider_ref = session_id (cs_xxx).
      # invoice.payment_intent retourne un payment_intent_id (pi_xxx) — différent !
      # Sans ce fix, find_or_initialize_by(pi_xxx) crée un 2ème enregistrement
      # et le paiement original reste "pending" éternellement sur le dashboard.
      payment = subscription.payments.where(status: "pending")
                            .order(created_at: :desc).first

      pi = invoice.payment_intent.to_s.presence || invoice.id.to_s

      unless payment
        # Pas de pending → renouvellement ou 2ème tentative : idempotent sur payment_intent
        payment = user.payments.find_or_initialize_by(provider_ref: pi)
      end

      # Montant : Stripe envoie des centimes (entier). Pour les renouvellements avec
      # remise 100 % (amount_paid == 0), on utilise 1 pour passer la validation > 0.
      amount = invoice.amount_paid.to_i > 0 ? invoice.amount_paid.to_i : 1

      payment.assign_attributes(
        subscription:      subscription,
        amount:            amount,
        currency:          invoice.currency.to_s.upcase,
        provider:          "stripe",
        status:            "success",
        provider_response: invoice.to_json,
        paid_at:           Time.at(invoice.created).utc
      )
      payment.save!
    rescue => e
      # L'enregistrement comptable a échoué, mais le plan EST activé (étape 1 réussie).
      # On log l'erreur sans relancer l'exception — le webhook retourne 200 à Stripe.
      Rails.logger.error("[StripeService] invoice.paid paiement non enregistré pour #{user.email}: #{e.message}")
    end

    # ── ÉTAPE 3 : Notification email ───────────────────────────────────────────
    UserMailer.subscription_activated(user, expires_at, plan_level: plan_level).deliver_later rescue nil
  end

  # ── invoice.payment_failed ────────────────────────────────────────────────────
  # Stripe retentera automatiquement (Smart Retries).
  # On ne dégrade PAS immédiatement, on notifie juste l'utilisateur.

  def handle_invoice_payment_failed(event)
    invoice = event.data.object
    user    = User.find_by(stripe_customer_id: invoice.customer)
    return unless user

    subscription = Subscription.find_by(stripe_subscription_id: invoice_subscription_id(invoice))

    if subscription
      # Premier paiement jamais reussi (pending/incomplete) :
      # retrograder immediatement en free pour eviter acces premium gratuit.
      first_payment_failure = subscription.payments.where(status: "success").none? &&
                              subscription.status.in?(%w[pending incomplete])

      if first_payment_failure
        subscription.update!(status: "cancelled", expires_at: Time.current) rescue nil
        user.update!(plan: "free", subscription_expires_at: nil) rescue nil
        Rails.logger.warn("[StripeService] invoice.payment_failed (1er paiement) : #{user.email} -> retrograde free")
      else
        # Renouvellement echoue -> garder acces pendant les relances Stripe
        subscription.update!(status: "past_due") rescue nil
        Rails.logger.warn("[StripeService] invoice.payment_failed (renouvellement) : #{user.email} -> past_due")
      end
    end

    UserMailer.payment_failed(user).deliver_later rescue nil
  end

  # ── customer.subscription.deleted ────────────────────────────────────────────
  # L'abonnement est résilié (annulation ou échec définitif).
  # On repasse l'utilisateur en Free.

  def handle_subscription_deleted(event)
    stripe_sub   = event.data.object
    user         = User.find_by(stripe_customer_id: stripe_sub.customer)
    subscription = Subscription.find_by(stripe_subscription_id: stripe_sub.id)

    subscription&.update!(status: "cancelled", expires_at: Time.current) rescue nil

    if user
      user.update!(plan: "free", subscription_expires_at: nil)
      Rails.logger.info("Stripe subscription.deleted : #{user.email} → free")
    end
  end

  # ── customer.subscription.updated ────────────────────────────────────────────
  # Changement de plan, pause, reprise… On synchronise expires_at, le statut
  # ET le plan utilisateur (cas où invoice.paid n'a pas encore été traité).

  def handle_subscription_updated(event)
    stripe_sub   = event.data.object
    subscription = Subscription.find_by(stripe_subscription_id: stripe_sub.id)
    return unless subscription

    expires_at = begin
      Time.at(period_end(stripe_sub)).utc
    rescue => e
      Rails.logger.warn("[StripeService] period_end échoué dans subscription.updated (#{e.message}) — expires_at inchangé")
      subscription.expires_at || Time.current + 1.month
    end
    status_map = { "active" => "active", "past_due" => "past_due", "canceled" => "cancelled" }
    new_status = status_map[stripe_sub.status] || subscription.status

    subscription.update!(status: new_status, expires_at: expires_at)

    # Mettre à jour le plan utilisateur quand la subscription devient active.
    # Cela couvre le cas où customer.subscription.updated arrive AVANT invoice.paid
    # (ordre des webhooks Stripe non garanti), évitant que user.plan reste "free".
    user_attrs = { subscription_expires_at: expires_at }
    if new_status == "active"
      user_attrs[:plan]          = plan_level_from_subscription(subscription)
      user_attrs[:trial_ends_at] = nil   # Souscription active → fin de l'essai Starter
    end
    subscription.user.update!(user_attrs)

    Rails.logger.info("Stripe subscription.updated : #{subscription.user.email} → #{new_status} (#{user_attrs[:plan] || 'plan inchangé'}) until #{expires_at.strftime('%d/%m/%Y')}")
  end

  def log_warn(msg)
    Rails.logger.warn("[StripeService] #{msg}")
  end

  # Mappe nos locales internes vers des locales Stripe valides.
  # Stripe ref : https://docs.stripe.com/js/appendix/supported_locales
  def stripe_locale_for(locale)
    case locale.to_s.downcase
    when "fr"         then "fr"
    when "de"         then "de"
    when "es"         then "es"
    when "pt"         then "pt"
    when "en", "us"   then "en"
    when "it"         then "it"
    when "nl"         then "nl"
    when "ja"         then "ja"
    when "zh"         then "zh"
    else                   "fr"   # fallback
    end
  end

  # Extrait le stripe_subscription_id depuis un objet Invoice Stripe,
  # compatible avec l'ancienne API (invoice.subscription)
  # ET la nouvelle API 2026-04-22.dahlia (invoice.parent.subscription_details.subscription).
  def invoice_subscription_id(invoice)
    # Ancien format : invoice.subscription = "sub_xxx"
    sub_id = invoice.respond_to?(:subscription) ? invoice.subscription.presence : nil
    return sub_id if sub_id.present?

    # Nouveau format (2026-04-22.dahlia) : invoice.parent.subscription_details.subscription
    parent = invoice.respond_to?(:parent) ? invoice.parent : nil
    return nil unless parent

    if parent.respond_to?(:subscription_details) && parent.subscription_details.present?
      parent.subscription_details.subscription.presence
    else
      nil
    end
  rescue => e
    Rails.logger.warn("[StripeService] invoice_subscription_id extraction failed: #{e.message}")
    nil
  end

  # Retourne le niveau de plan normalisé ("starter" | "pro" | "premium")
  # à partir du slug de la Subscription locale.
  # Gère tous les formats : "premium", "premium_12m", "premium-annual",
  #                         "starter", "starter_12m", "pro", "pro-monthly", etc.
  def plan_level_from_subscription(subscription)
    slug = subscription.plan.to_s.downcase
    # Correspondance par préfixe (avant _ ou -) — ordre : du plus spécifique au moins
    return "premium" if slug.match?(/\Apremium/) || slug.include?("premium")
    return "pro"     if slug.match?(/\Apro[_\-]?/) || slug == "pro"
    return "starter" if slug.match?(/\Astarter/)
    # Fallback : chercher le plan Rails et extraire le préfixe avant _ ou -
    plan = Plan.find_by(slug: slug)
    if plan
      plan.slug.gsub(/[_\-].*\z/, "")   # "starter_12m" → "starter", "premium-annual" → "premium"
    else
      Rails.logger.warn("[StripeService] plan_level_from_subscription: slug inconnu '#{slug}' → fallback premium")
      "premium"
    end
  end

  # ── Compatibilité nouvelle API Stripe ────────────────────────────────────────
  # Depuis l'API 2024-09+, current_period_end/start est dans items.data[0]
  # et non plus à la racine du Subscription object.

  def period_end(stripe_sub)
    stripe_sub.respond_to?(:current_period_end) && stripe_sub.current_period_end.present? \
      ? stripe_sub.current_period_end \
      : stripe_sub.items.data.first.current_period_end
  end

  def period_start(stripe_sub)
    stripe_sub.respond_to?(:current_period_start) && stripe_sub.current_period_start.present? \
      ? stripe_sub.current_period_start \
      : stripe_sub.items.data.first.current_period_start
  end

  # monthly → ["month", 1] | quarterly → ["month", 3] | semi_annual → ["month", 6] | yearly → ["year", 1]
  def stripe_interval(billing_frequency)
    case billing_frequency
    when "monthly"    then ["month", 1]
    when "quarterly"  then ["month", 3]
    when "semi_annual" then ["month", 6]  # BUG FIXÉ : était traité comme mensuel (fallback else)
    when "yearly"     then ["year",  1]
    else
      Rails.logger.warn("[StripeService] billing_frequency inconnu : #{billing_frequency.inspect} — fallback mensuel")
      ["month", 1]
    end
  end
end
