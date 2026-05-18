class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string  :name,              null: false
      t.string  :slug,              null: false
      t.text    :description
      t.integer :price_ariary,      null: false, default: 0
      t.string  :billing_frequency, null: false, default: "monthly"
      t.text    :features_json,     default: "[]"
      t.text    :operators_json,    default: "[]"
      t.string  :badge
      t.string  :status,            default: "draft"
      t.integer :position,          default: 0
      t.timestamps
    end
    add_index :plans, :slug,   unique: true
    add_index :plans, :status
  end
end
