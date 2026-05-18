class AddPricesJsonToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :prices_json, :text, default: '{}'
  end
end
