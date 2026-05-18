class CreatePromoCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :promo_codes do |t|
      t.string  :code,                   null: false
      t.string  :discount_type,          null: false, default: "percent"
      t.decimal :discount_value,         precision: 10, scale: 2, null: false
      t.text    :applicable_plans_json,  default: "[]"
      t.datetime :starts_at
      t.datetime :expires_at
      t.integer :max_uses_total
      t.integer :max_uses_per_user,      default: 1
      t.integer :uses_count,             default: 0
      t.string  :status,                 default: "active"
      t.timestamps
    end
    add_index :promo_codes, :code,   unique: true
    add_index :promo_codes, :status
  end
end
