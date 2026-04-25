class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string  :name,             null: false
      t.string  :email,            null: false, index: { unique: true }
      t.string  :phone,            null: false   # numéro mobile money
      t.string  :country,          default: "CI" # CI, SN, CM, ML...
      t.string  :password_digest,  null: false
      t.string  :status,           default: "active"  # active | suspended | deleted
      t.string  :plan,             default: "free"    # free | premium
      t.datetime :subscription_expires_at
      t.string  :device_token   # FCM pour notifications push

      t.timestamps
    end
  end
end
