class AddStripeFields < ActiveRecord::Migration[8.0]
  def change
    # Stripe customer ID sur les utilisateurs
    add_column :users, :stripe_customer_id, :string

    # Stripe fields sur les abonnements
    add_column :subscriptions, :stripe_subscription_id,  :string
    add_column :subscriptions, :stripe_payment_intent_id, :string

    # Stripe price ID + prix USD sur les plans tarifaires
    add_column :plans, :stripe_price_id,  :string
    add_column :plans, :price_usd_cents,  :integer, default: 0, null: false

    add_index :users,         :stripe_customer_id,         unique: true, where: "stripe_customer_id IS NOT NULL"
    add_index :subscriptions, :stripe_subscription_id,     unique: true, where: "stripe_subscription_id IS NOT NULL"
    add_index :subscriptions, :stripe_payment_intent_id,   unique: true, where: "stripe_payment_intent_id IS NOT NULL"
  end
end
