class CreateLegalDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :legal_documents do |t|
      t.string  :document_type, null: false, default: "rgpd"
      t.string  :region,        null: false, default: "eu"
      t.string  :version
      t.boolean :active,        null: false, default: false
      t.text    :notes
      t.integer :admin_user_id

      t.timestamps
    end

    add_index :legal_documents, %i[document_type region active]
  end
end
