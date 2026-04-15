# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_04_15_152500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "auctions", force: :cascade do |t|
    t.string "state", null: false
    t.string "county", null: false
    t.string "jurisdiction"
    t.string "auction_type", default: "tax_deed", null: false
    t.date "sale_date", null: false
    t.date "registration_deadline"
    t.date "bidding_start"
    t.integer "parcel_count", default: 0
    t.decimal "total_amount", precision: 15, scale: 2
    t.string "status", default: "upcoming"
    t.string "bidding_url", limit: 500
    t.decimal "latitude", precision: 10, scale: 8
    t.decimal "longitude", precision: 11, scale: 8
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "registration_opens"
    t.date "end_date"
    t.string "source_url", limit: 500
    t.index ["county", "state", "sale_date"], name: "idx_auctions_county_state_date", unique: true
    t.index ["sale_date"], name: "index_auctions_on_sale_date"
    t.index ["state"], name: "index_auctions_on_state"
    t.index ["status"], name: "index_auctions_on_status"
  end

  create_table "parcel_liens", force: :cascade do |t|
    t.bigint "parcel_id", null: false
    t.string "lender_name", limit: 200
    t.string "lien_type", limit: 30
    t.decimal "amount", precision: 12, scale: 2
    t.date "recorded_date"
    t.string "status", limit: 20
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parcel_id"], name: "index_parcel_liens_on_parcel_id"
  end

  create_table "parcel_user_notes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "parcel_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parcel_id"], name: "index_parcel_user_notes_on_parcel_id"
    t.index ["user_id", "parcel_id"], name: "index_parcel_user_notes_on_user_id_and_parcel_id"
    t.index ["user_id"], name: "idx_pun_user_id_rls"
    t.index ["user_id"], name: "index_parcel_user_notes_on_user_id"
  end

  create_table "parcel_user_tags", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "parcel_id", null: false
    t.string "tag", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parcel_id"], name: "index_parcel_user_tags_on_parcel_id"
    t.index ["tag"], name: "index_parcel_user_tags_on_tag"
    t.index ["user_id", "parcel_id"], name: "index_parcel_user_tags_on_user_id_and_parcel_id", unique: true
    t.index ["user_id"], name: "idx_put_user_id_rls"
    t.index ["user_id"], name: "index_parcel_user_tags_on_user_id"
  end

  create_table "parcels", force: :cascade do |t|
    t.bigint "auction_id"
    t.text "parcel_id", null: false
    t.text "address"
    t.text "property_address"
    t.text "city"
    t.text "state", null: false
    t.text "county", null: false
    t.text "zip"
    t.decimal "latitude", precision: 10, scale: 8
    t.decimal "longitude", precision: 11, scale: 8
    t.text "owner_name"
    t.text "owner_mail_address"
    t.text "legal_description"
    t.decimal "delinquent_amount", precision: 12, scale: 2
    t.decimal "opening_bid", precision: 12, scale: 2
    t.decimal "assessed_value", precision: 15, scale: 2
    t.decimal "land_value", precision: 15, scale: 2
    t.decimal "improvement_value", precision: 15, scale: 2
    t.decimal "market_value", precision: 15, scale: 2
    t.decimal "estimated_sale_value", precision: 12, scale: 2
    t.decimal "price_per_acre", precision: 12, scale: 2
    t.integer "year_built"
    t.decimal "sqft_living", precision: 10, scale: 2
    t.decimal "sqft_lot", precision: 12, scale: 2
    t.decimal "lot_area_acres", precision: 10, scale: 4
    t.text "minimum_lot_size"
    t.text "zoning"
    t.text "jurisdiction"
    t.text "land_use"
    t.text "property_type"
    t.integer "bedrooms"
    t.decimal "bathrooms", precision: 3, scale: 1
    t.text "lot_shape"
    t.string "homestead_flag", limit: 20
    t.string "crime_level", limit: 20
    t.string "electric", limit: 100
    t.string "water", limit: 100
    t.string "sewer", limit: 100
    t.string "hoa", limit: 100
    t.boolean "wetlands"
    t.text "fema_risk_level"
    t.text "fema_notes"
    t.string "fema_url", limit: 500
    t.string "regrid_url", limit: 500
    t.string "gis_image_url", limit: 500
    t.string "google_maps_url", limit: 500
    t.string "property_image_url", limit: 500
    t.string "clerk_url", limit: 500
    t.string "tax_collector_url", limit: 500
    t.string "auction_status", default: "available"
    t.decimal "winning_bid", precision: 12, scale: 2
    t.string "data_source", default: "google_sheets"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auction_id"], name: "index_parcels_on_auction_id"
    t.index ["latitude", "longitude"], name: "idx_parcels_lat_lng"
    t.index ["parcel_id"], name: "index_parcels_on_parcel_id"
    t.index ["state", "county", "parcel_id"], name: "idx_parcels_unique_state_county_pid", unique: true
    t.index ["state", "county"], name: "idx_parcels_state_county"
  end

  create_table "reports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "parcel_id", null: false
    t.string "report_type", limit: 30, null: false
    t.string "status", default: "pending"
    t.integer "file_size_bytes"
    t.datetime "ordered_at"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "admin_notes"
    t.string "datatrace_order_ref", limit: 200
    t.index ["parcel_id"], name: "index_reports_on_parcel_id"
    t.index ["user_id", "parcel_id", "report_type"], name: "idx_reports_user_parcel_type", unique: true, where: "((status)::text <> 'failed'::text)"
    t.index ["user_id"], name: "idx_rep_user_id_rls"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "stripe_subscription_id"
    t.string "stripe_price_id"
    t.string "plan_name", default: "standard", null: false
    t.string "status", default: "trial", null: false
    t.integer "trial_amount_cents", default: 199
    t.integer "annual_amount_cents", default: 49700
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "canceled_at"
    t.integer "limit_parcels", default: 500, null: false
    t.integer "limit_avm", default: 15, null: false
    t.integer "limit_scope", default: 2, null: false
    t.integer "limit_title", default: 0, null: false
    t.integer "used_parcels", default: 0, null: false
    t.integer "used_avm", default: 0, null: false
    t.integer "used_scope", default: 0, null: false
    t.boolean "title_search_used", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["user_id"], name: "idx_sub_user_id_rls"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "sync_logs", force: :cascade do |t|
    t.string "status", default: "running", null: false
    t.integer "parcels_added", default: 0
    t.integer "parcels_updated", default: 0
    t.integer "parcels_skipped", default: 0
    t.float "duration_seconds"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["started_at"], name: "index_sync_logs_on_started_at"
    t.index ["status"], name: "index_sync_logs_on_status"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "first_name"
    t.string "last_name"
    t.string "phone"
    t.string "stripe_customer_id"
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "viewed_parcels", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "parcel_id", null: false
    t.datetime "viewed_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parcel_id"], name: "index_viewed_parcels_on_parcel_id"
    t.index ["user_id", "parcel_id"], name: "idx_viewed_parcels_user_parcel", unique: true
    t.index ["user_id"], name: "idx_vp_user_id_rls"
    t.index ["user_id"], name: "index_viewed_parcels_on_user_id"
  end

  add_foreign_key "parcel_liens", "parcels"
  add_foreign_key "parcel_user_notes", "parcels"
  add_foreign_key "parcel_user_notes", "users"
  add_foreign_key "parcel_user_tags", "parcels"
  add_foreign_key "parcel_user_tags", "users"
  add_foreign_key "parcels", "auctions"
  add_foreign_key "reports", "parcels"
  add_foreign_key "reports", "users"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "viewed_parcels", "parcels"
  add_foreign_key "viewed_parcels", "users"
end
