class AddBodyEntriesToUsers < ActiveRecord::Migration[8.0]
  def change
    # Historique des mesures corporelles (poids, taille, tour de taille…) — JSON array
    add_column :users, :body_entries_data, :text
  end
end
