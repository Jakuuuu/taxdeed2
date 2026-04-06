# frozen_string_literal: true

class CreateParcelUserNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :parcel_user_notes do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :parcel, null: false, foreign_key: true
      t.text       :body,   null: false

      t.timestamps
    end

    # Múltiples notas por usuario+parcela → sin unique constraint
    add_index :parcel_user_notes, %i[user_id parcel_id]
  end
end
