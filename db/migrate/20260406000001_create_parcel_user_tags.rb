# frozen_string_literal: true

class CreateParcelUserTags < ActiveRecord::Migration[7.1]
  def change
    create_table :parcel_user_tags do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :parcel, null: false, foreign_key: true
      t.string     :tag,    null: false

      t.timestamps
    end

    # Solo un tag por usuario+parcela (UPSERT semántico)
    add_index :parcel_user_tags, %i[user_id parcel_id], unique: true
    add_index :parcel_user_tags, :tag
  end
end
