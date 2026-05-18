class AddStripeProductIdToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :stripe_product_id, :string unless column_exists?(:plans, :stripe_product_id)
  end
end
