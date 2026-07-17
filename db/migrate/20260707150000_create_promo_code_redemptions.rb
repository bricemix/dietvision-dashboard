class CreatePromoCodeRedemptions < ActiveRecord::Migration[8.0]
  def change
    create_table :promo_code_redemptions do |t|
      t.references :user,       null: false, foreign_key: true
      t.references :promo_code, null: false, foreign_key: true
      t.references :payment,    foreign_key: true
      t.string     :stripe_session_id
      t.timestamps
    end

    add_index :promo_code_redemptions, :stripe_session_id, unique: true,
              where: "stripe_session_id IS NOT NULL"
    add_index :promo_code_redemptions, [:promo_code_id, :user_id]
  end
end
