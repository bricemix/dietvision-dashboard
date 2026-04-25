class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions do |t|
      t.references :user,     null: false, foreign_key: true
      t.string  :plan,        null: false   # monthly | yearly
      t.decimal :amount,      precision: 10, scale: 2, null: false
      t.string  :currency,    default: "XOF"  # XOF (CFA), XAF, GNF...
      t.string  :status,      default: "pending"  # pending | active | expired | cancelled
      t.datetime :starts_at
      t.datetime :expires_at

      t.timestamps
    end
  end
end
