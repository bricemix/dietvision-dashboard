class CreateSavedPushTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :saved_push_templates do |t|
      t.string :name,  null: false
      t.string :title, null: false
      t.text   :body,  null: false
      t.timestamps
    end
  end
end
