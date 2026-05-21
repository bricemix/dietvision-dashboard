class AddStripeIdsToPromoCodes < ActiveRecord::Migration[8.0]
  def change
    add_column :promo_codes, :stripe_coupon_id,         :string
    add_column :promo_codes, :stripe_promotion_code_id, :string

    add_index :promo_codes, :stripe_coupon_id,         unique: true, where: "stripe_coupon_id IS NOT NULL"
    add_index :promo_codes, :stripe_promotion_code_id, unique: true, where: "stripe_promotion_code_id IS NOT NULL"
  end
end
