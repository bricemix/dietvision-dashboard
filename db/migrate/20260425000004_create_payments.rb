class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :user,         null: false, foreign_key: true
      t.references :subscription, null: true,  foreign_key: true
      t.decimal :amount,          precision: 10, scale: 2, null: false
      t.string  :currency,        default: "XOF"
      t.string  :provider,        null: false  # cinetpay | mtn | orange | wave
      t.string  :provider_ref                  # référence transaction chez le provider
      t.string  :transaction_id,  index: { unique: true }
      t.string  :phone_number                  # numéro mobile money utilisé
      t.string  :status,          default: "pending"  # pending | success | failed | refunded
      t.text    :provider_response             # réponse JSON brute du provider
      t.datetime :paid_at

      t.timestamps
    end
  end
end
