class AddTranslationsToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :translations_json, :text, default: "{}"
  end
end
