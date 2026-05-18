class AddFeaturesExcludedToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :features_excluded_json, :text, default: "[]"
    add_column :plans, :original_price_eur_cents, :integer, default: 0  # barré (promo)
    add_column :plans, :cta_label, :string, default: "Essayer 7 jours gratuits"
    add_column :plans, :cta_style, :string, default: "outline"  # outline | lime | dark
  end
end
