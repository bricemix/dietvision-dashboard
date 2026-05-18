# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_28_000001) do
  create_table "admin_logs", force: :cascade do |t|
    t.integer "admin_user_id"
    t.string "action", null: false
    t.string "resource_type"
    t.integer "resource_id"
    t.text "details_json"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_admin_logs_on_admin_user_id"
    t.index ["created_at"], name: "index_admin_logs_on_created_at"
    t.index ["resource_type", "resource_id"], name: "index_admin_logs_on_resource_type_and_resource_id"
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "admin"
    t.datetime "last_login_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
  end

  create_table "api_usages", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "endpoint", null: false
    t.string "model"
    t.integer "input_tokens", default: 0
    t.integer "output_tokens", default: 0
    t.decimal "cost_usd", precision: 10, scale: 6, default: "0.0"
    t.string "status", default: "success"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_api_usages_on_created_at"
    t.index ["user_id", "created_at"], name: "index_api_usages_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_api_usages_on_user_id"
  end

  create_table "app_configs", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_configs_on_key", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "subscription_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "XOF"
    t.string "provider", null: false
    t.string "provider_ref"
    t.string "transaction_id"
    t.string "phone_number"
    t.string "status", default: "pending"
    t.text "provider_response"
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscription_id"], name: "index_payments_on_subscription_id"
    t.index ["transaction_id"], name: "index_payments_on_transaction_id", unique: true
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.integer "price_ariary", default: 0, null: false
    t.string "billing_frequency", default: "monthly", null: false
    t.text "features_json", default: "[]"
    t.text "operators_json", default: "[]"
    t.string "badge"
    t.string "status", default: "draft"
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_price_id"
    t.integer "price_usd_cents", default: 0, null: false
    t.text "prices_json", default: "{}"
    t.index ["slug"], name: "index_plans_on_slug", unique: true
    t.index ["status"], name: "index_plans_on_status"
  end

  create_table "promo_codes", force: :cascade do |t|
    t.string "code", null: false
    t.string "discount_type", default: "percent", null: false
    t.decimal "discount_value", precision: 10, scale: 2, null: false
    t.text "applicable_plans_json", default: "[]"
    t.datetime "starts_at"
    t.datetime "expires_at"
    t.integer "max_uses_total"
    t.integer "max_uses_per_user", default: 1
    t.integer "uses_count", default: 0
    t.string "status", default: "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_promo_codes_on_code", unique: true
    t.index ["status"], name: "index_promo_codes_on_status"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "plan", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "XOF"
    t.string "status", default: "pending"
    t.datetime "starts_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_subscription_id"
    t.string "stripe_payment_intent_id"
    t.index ["stripe_payment_intent_id"], name: "index_subscriptions_on_stripe_payment_intent_id", unique: true, where: "stripe_payment_intent_id IS NOT NULL"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true, where: "stripe_subscription_id IS NOT NULL"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "phone", null: false
    t.string "country", default: "CI"
    t.string "password_digest", null: false
    t.string "status", default: "active"
    t.string "plan", default: "free"
    t.datetime "subscription_expires_at"
    t.string "device_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "trial_ends_at"
    t.boolean "had_trial", default: false, null: false
    t.string "stripe_customer_id"
    t.text "fitai_profile"
    t.text "planning_data"
    t.text "body_entries_data"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true, where: "stripe_customer_id IS NOT NULL"
    t.index ["trial_ends_at"], name: "index_users_on_trial_ends_at"
  end

  add_foreign_key "api_usages", "users"
  add_foreign_key "payments", "subscriptions"
  add_foreign_key "payments", "users"
  add_foreign_key "subscriptions", "users"
end
