class AddLocaleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :locale, :string, default: "fr", null: false
  end
end
