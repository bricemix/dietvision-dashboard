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

ActiveRecord::Schema[8.0].define(version: 2026_04_25_000006) do
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
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "api_usages", "users"
  add_foreign_key "payments", "subscriptions"
  add_foreign_key "payments", "users"
  add_foreign_key "subscriptions", "users"
end
