class AddMealsDataToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :meals_data, :text
  end
end
