class StripeService
  def initialize
    Stripe.api_key = AppConfig.stripe_secret_key || ENV["STRIPE_SECRET_KEY"]
  end

  # ── Customer ─────────────────────────────────────────────────────────────────
  # Crée ou retrouve le Customer Stripe lié à l'utilisateur.
  # La colonne stripe_customer_id est le seul lien fiable entre les deux systèmes.

  def find_or_create_customer(user)
    if user.stripe_customer_id.present?
      Stripe::Customer.retrieve(user.stripe_customer_id)
    else
      customer = Stripe::Customer.create(
        email:    user.email,
        name:     user.name,
        metadata: { user_id: user.id, app: "dietvision" }
      )
      user.update_column(:stripe_customer_id, customer.id)
      customer
    end
  rescue Stripe::InvalidRequestError => e
    # Customer supprimé côté Stripe → on en recrée un
    Rails.logger.warn("Stripe customer #{user.stripe_customer_id} introuvable, recréation : #{e.message}")
    customer = Stripe::Customer.create(
      email:    user.email,
      name:     user.name,
      metadata: { user_id: user.id, app: "dietvision" }
    )
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
      Stripe::Product.retrieve(plan.stripe_product_id) rescue nil
    end

    if product.nil?
      product = Stripe::Product.create(
        name:        plan.name,
        description: plan.description.presence || plan.name,
        metadata:    { plan_id: plan.id, plan_slug: plan.slug, app: "dietvision" }
      )
      plan.update_column(:stripe_product_id, product.id)
    else
      # Mettre à jour le nom si changé
      Stripe::Product.update(product.id, name: plan.name) rescue nil
    end

    # 2. Archiver l'ancien prix si existant (Stripe ne permet pas de modifier un prix)
    if plan.stripe_price_id.present?
      Stripe::Price.update(plan.stripe_price_id, active: false) rescue nil
    end

    # 3. Créer le nouveau prix récurrent
    price_params = {
      product:   product.id,
      unit_amount: plan.price_eur_cents.to_i,
      currency:  "eur",
      recurring: { interval: interval }.tap { |h| h[:interval_count] = interval_count if interval_count > 1 },
      metadata:  { plan_id: plan.id, plan_slug: plan.slug }
    }

    price = Stripe::Price.create(price_params)
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
      Stripe::Coupon.retrieve(promo_code.stripe_coupon_id) rescue nil
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

      coupon = Stripe::Coupon.create(coupon_params)
      promo_code.update_column(:stripe_coupon_id, coupon.id)
    end

    # 2. Créer le PromotionCode Stripe (le code visible par l'utilisateur)
    # Si un code existe déjà côté Stripe, on l'archive et on en recrée un
    if promo_code.stripe_promotion_code_id.present?
      begin
        Stripe::PromotionCode.update(promo_code.stripe_promotion_code_id, active: false)
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

    promotion = Stripe::PromotionCode.create(promo_params)
    promo_code.update_column(:stripe_promotion_code_id, promotion.id)

    Rails.logger.info("Stripe sync promo : #{promo_code.code} → coupon #{coupon.id} / promo #{promotion.id}")
    promotion.id
  end

  # ── Checkout Session (mode: subscription) ────────────────────────────────────
  # Retourne une URL Stripe Checkout.
  # mode: "subscription" → facturation récurrente gérée à 100% par Stripe.
  # NE PAS utiliser mode: "payment" pour les abonnements.

  def create_checkout_session(user:, plan:)
    raise ArgumentError, "Plan sans Stripe Price ID" if plan.stripe_price_id.blank?

    customer = find_or_create_customer(user)

    session = Stripe::Checkout::Session.create(
      customer:    customer.id,
      line_items:  [{ price: plan.stripe_price_id, quantity: 1 }],
      mode:        "subscription",
      allow_promotion_codes: true,           # ← Champ "Code promo" sur la page Stripe
      success_url: "https://api.diet-vision.com/payment/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url:  "https://api.diet-vision.com/payment/cancel",
      subscription_data: {
        metadata: { user_id: user.id, plan_id: plan.id, plan_slug: plan.slug }
      },
      metadata: { user_id: user.id, plan_id: plan.id, plan_slug: plan.slug }
    )

    { checkout_url: session.url, session_id: session.id }
  end

  # ── Webhook dispatcher ────────────────────────────────────────────────────────

  def construct_event(payload, signature)
    webhook_secret = AppConfig.stripe_webhook_secret || ENV["STRIPE_WEBHOOK_SECRET"]
    Stripe::Webhook.construct_event(payload, signature, webhook_secret)
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

    Rails.logger.info("Stripe checkout.completed : #{user.email} → sub #{stripe_subscription_id}")
  end

  # ── invoice.paid ──────────────────────────────────────────────────────────────
  # Déclenché à chaque paiement réussi (création ET renouvellement).
  # C'est ici qu'on active ou prolonge l'accès Premium.
  # expires_at est défini par Stripe (current_period_end) — JAMAIS calculé en dur.

  def handle_invoice_paid(event)
    invoice                = event.data.object
    stripe_subscription_id = invoice.subscription
    return unless stripe_subscription_id.present?

    user = User.find_by(stripe_customer_id: invoice.customer)
    return log_warn("invoice.paid : aucun user pour customer #{invoice.customer}") unless user

    # Récupérer la vraie date de fin depuis Stripe
    stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id)
    expires_at = Time.at(period_end(stripe_sub)).utc

    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription_id) ||
                   user.subscriptions.where(status: %w[pending active past_due])
                       .order(created_at: :desc).first

    return log_warn("invoice.paid : aucune subscription pour #{stripe_subscription_id}") unless subscription

    ActiveRecord::Base.transaction do
      # Enregistrer le paiement (idempotent sur payment_intent)
      payment = user.payments.find_or_initialize_by(provider_ref: invoice.payment_intent.to_s)
      payment.assign_attributes(
        subscription:      subscription,
        amount:            invoice.amount_paid,
        currency:          invoice.currency.upcase,
        provider:          "stripe",
        status:            "success",
        provider_response: invoice.to_json,
        paid_at:           Time.at(invoice.created).utc
      )
      payment.save!

      # Activer l'abonnement avec la vraie période Stripe
      subscription.update!(
        stripe_subscription_id: stripe_subscription_id,
        status:     "active",
        starts_at:  Time.at(period_start(stripe_sub)).utc,
        expires_at: expires_at
      )

      # Passer l'utilisateur au bon plan selon le slug de l'abonnement
      plan_level = plan_level_from_subscription(subscription)
      user.update!(
        plan:                    plan_level,
        subscription_expires_at: expires_at
      )
    end

    # Notification email (hors transaction pour ne pas bloquer en cas d'échec SMTP)
    UserMailer.subscription_activated(user, expires_at).deliver_later rescue nil

    Rails.logger.info("Stripe invoice.paid : #{user.email} premium jusqu'au #{expires_at.strftime('%d/%m/%Y')}")
  end

  # ── invoice.payment_failed ────────────────────────────────────────────────────
  # Stripe retentera automatiquement (Smart Retries).
  # On ne dégrade PAS immédiatement, on notifie juste l'utilisateur.

  def handle_invoice_payment_failed(event)
    invoice = event.data.object
    user    = User.find_by(stripe_customer_id: invoice.customer)
    return unless user

    # Passer en past_due (accès conservé le temps des relances Stripe)
    subscription = Subscription.find_by(stripe_subscription_id: invoice.subscription)
    subscription&.update!(status: "past_due") rescue nil

    Rails.logger.warn("Stripe invoice.payment_failed : #{user.email}")
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
  # Changement de plan, pause, reprise… On synchronise expires_at et le statut.

  def handle_subscription_updated(event)
    stripe_sub   = event.data.object
    subscription = Subscription.find_by(stripe_subscription_id: stripe_sub.id)
    return unless subscription

    expires_at = Time.at(period_end(stripe_sub)).utc
    status_map = { "active" => "active", "past_due" => "past_due", "canceled" => "cancelled" }
    new_status = status_map[stripe_sub.status] || subscription.status

    subscription.update!(status: new_status, expires_at: expires_at)
    subscription.user.update!(subscription_expires_at: expires_at)

    Rails.logger.info("Stripe subscription.updated : #{subscription.user.email} → #{new_status} until #{expires_at.strftime('%d/%m/%Y')}")
  end

  def log_warn(msg)
    Rails.logger.warn("[StripeService] #{msg}")
  end

  # Retourne le niveau de plan ("starter" | "pro" | "premium") à partir du slug
  # de la Subscription locale (ex: "pro", "starter", "premium-annual" → "premium")
  def plan_level_from_subscription(subscription)
    slug = subscription.plan.to_s.downcase
    case slug
    when "starter"                      then "starter"
    when "pro"                          then "pro"
    when /premium/                      then "premium"
    else
      # Fallback : lire le plan Rails via stripe_price_id
      plan = Plan.find_by(slug: slug)
      plan ? plan.slug.gsub(/-.*/, "") : "premium"
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
