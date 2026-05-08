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

ActiveRecord::Schema[7.2].define(version: 2026_05_08_200000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "admin_audit_logs", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.bigint "target_user_id", null: false
    t.string "action", null: false
    t.text "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_admin_audit_logs_on_action"
    t.index ["admin_user_id"], name: "index_admin_audit_logs_on_admin_user_id"
    t.index ["created_at"], name: "index_admin_audit_logs_on_created_at"
    t.index ["target_user_id"], name: "index_admin_audit_logs_on_target_user_id"
  end

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

  create_table "county_market_stats", force: :cascade do |t|
    t.string "state", null: false
    t.string "county", null: false
    t.string "modalidad"
    t.text "about"
    t.text "borders"
    t.string "city_1"
    t.string "city_2"
    t.string "city_3"
    t.string "google_maps_url"
    t.string "redfin_url"
    t.string "county_image_url"
    t.string "census_url"
    t.string "fred_url"
    t.string "realtor_url"
    t.string "budgets_url"
    t.string "bea_url"
    t.string "faq_url"
    t.string "market_status"
    t.string "crime_rating"
    t.string "flood_risk"
    t.integer "population"
    t.decimal "gdp", precision: 15, scale: 2
    t.decimal "median_household_income", precision: 15, scale: 2
    t.decimal "employment_rate", precision: 5, scale: 2
    t.decimal "unemployment_rate", precision: 5, scale: 2
    t.decimal "median_home_price", precision: 15, scale: 2
    t.decimal "price_per_sqft", precision: 10, scale: 2
    t.integer "active_listings"
    t.integer "days_on_market"
    t.decimal "annual_growth_rate", precision: 5, scale: 2
    t.decimal "annual_budget", precision: 15, scale: 2
    t.string "planning_zoning_contact"
    t.string "building_division_contact"
    t.string "clerk_office_contact"
    t.string "tax_collector_contact"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["market_status"], name: "index_county_market_stats_on_market_status"
    t.index ["state", "county"], name: "idx_county_stats_state_county", unique: true
  end

  create_table "credit_topups", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "stripe_payment_intent", limit: 100, null: false
    t.integer "credits_purchased", null: false
    t.integer "amount_cents", null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.datetime "purchased_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_credit_topups_on_user_id"
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "transaction_type", limit: 30, null: false
    t.integer "credits_delta", null: false
    t.integer "credits_balance_after", null: false
    t.bigint "parcel_id"
    t.string "stripe_payment_intent", limit: 100
    t.string "description", limit: 200
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["parcel_id"], name: "index_credit_transactions_on_parcel_id"
    t.index ["transaction_type"], name: "idx_credit_tx_type"
    t.index ["user_id", "created_at"], name: "idx_credit_tx_user_created"
    t.index ["user_id"], name: "index_credit_transactions_on_user_id"
  end

  create_table "export_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "parcels_exported", null: false
    t.string "export_format", limit: 10, default: "csv", null: false
    t.datetime "exported_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["user_id", "exported_at"], name: "idx_export_logs_user_exported"
    t.index ["user_id"], name: "index_export_logs_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "notifiable_type", null: false
    t.bigint "notifiable_id", null: false
    t.string "kind", null: false
    t.string "delivery_channel", default: "in_app", null: false
    t.datetime "read_at"
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable_type_and_notifiable_id"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
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

  create_table "parcel_watches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "parcel_id", null: false
    t.integer "notify_days_before", default: 7, null: false
    t.boolean "in_app_enabled", default: true, null: false
    t.boolean "email_enabled", default: false, null: false
    t.datetime "last_notified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parcel_id"], name: "index_parcel_watches_on_parcel_id"
    t.index ["user_id", "parcel_id"], name: "index_parcel_watches_on_user_id_and_parcel_id", unique: true
    t.index ["user_id"], name: "index_parcel_watches_on_user_id"
  end

  create_table "parcels", force: :cascade do |t|
    t.bigint "auction_id"
    t.string "parcel_id", limit: 50, null: false
    t.string "address", limit: 300
    t.string "property_address", limit: 300
    t.string "city", limit: 100
    t.string "state", limit: 100, null: false
    t.string "county", limit: 100, null: false
    t.string "zip", limit: 10
    t.decimal "latitude", precision: 10, scale: 8
    t.decimal "longitude", precision: 11, scale: 8
    t.string "owner_name", limit: 200
    t.string "owner_mail_address", limit: 300
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
    t.string "minimum_lot_size", limit: 150
    t.string "zoning", limit: 150
    t.string "jurisdiction", limit: 300
    t.string "land_use", limit: 200
    t.string "property_type", limit: 50
    t.integer "bedrooms"
    t.decimal "bathrooms", precision: 3, scale: 1
    t.string "lot_shape", limit: 50
    t.string "homestead_flag", limit: 100
    t.string "crime_level", limit: 50
    t.string "electric", limit: 10
    t.string "water", limit: 10
    t.string "sewer", limit: 10
    t.string "hoa", limit: 10
    t.boolean "wetlands"
    t.string "fema_risk_level", limit: 300
    t.text "fema_notes"
    t.string "fema_url", limit: 2048
    t.string "regrid_url", limit: 2048
    t.string "gis_image_url", limit: 2048
    t.string "google_maps_url", limit: 2048
    t.string "property_image_url", limit: 2048
    t.string "clerk_url", limit: 2048
    t.string "tax_collector_url", limit: 2048
    t.string "auction_status", default: "available"
    t.decimal "winning_bid", precision: 12, scale: 2
    t.string "data_source", default: "google_sheets"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sale_venue", comment: "Sale venue from Google Sheet"
    t.text "comments_do_va"
    t.decimal "price_estimate", precision: 12, scale: 2
    t.decimal "max_bid_30", precision: 12, scale: 2
    t.decimal "max_bid_35", precision: 12, scale: 2
    t.text "technical_analysis"
    t.string "property_appraiser_url", limit: 500
    t.string "clear_to_bid_grade"
    t.text "polygon_encoded"
    t.boolean "clear_to_bid_grade_locked", default: false, null: false
    t.text "polygon_geojson"
    t.datetime "polygon_fetched_at"
    t.index ["auction_id"], name: "index_parcels_on_auction_id"
    t.index ["clear_to_bid_grade"], name: "index_parcels_on_clear_to_bid_grade_not_null", where: "(clear_to_bid_grade IS NOT NULL)"
    t.index ["latitude", "longitude"], name: "idx_parcels_lat_lng"
    t.index ["parcel_id"], name: "index_parcels_on_parcel_id"
    t.index ["polygon_encoded"], name: "index_parcels_on_polygon_encoded_not_null", where: "(polygon_encoded IS NOT NULL)"
    t.index ["polygon_fetched_at"], name: "index_parcels_on_polygon_fetched_at_not_null", where: "(polygon_fetched_at IS NOT NULL)"
    t.index ["state", "county", "parcel_id"], name: "idx_parcels_unique_state_county_pid", unique: true
    t.index ["state", "county"], name: "idx_parcels_state_county"
  end

  create_table "pipeline_properties", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "parcel_id", null: false
    t.bigint "pipeline_stage_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "added_at", default: -> { "now()" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "notes"
    t.index ["parcel_id"], name: "index_pipeline_properties_on_parcel_id"
    t.index ["pipeline_stage_id", "position"], name: "idx_pipeline_props_stage"
    t.index ["pipeline_stage_id"], name: "index_pipeline_properties_on_pipeline_stage_id"
    t.index ["user_id", "parcel_id"], name: "idx_pipeline_props_user_parcel", unique: true
    t.index ["user_id"], name: "index_pipeline_properties_on_user_id"
  end

  create_table "pipeline_stages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", limit: 100, null: false
    t.string "emoji", limit: 10
    t.string "color", limit: 30
    t.integer "position", null: false
    t.boolean "is_default", default: false
    t.string "crm_tag_map", limit: 50
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "system_key", limit: 30
    t.index ["user_id", "position"], name: "idx_pipeline_stages_user"
    t.index ["user_id", "system_key"], name: "idx_pipeline_stages_user_system_key", where: "(system_key IS NOT NULL)"
    t.index ["user_id"], name: "index_pipeline_stages_on_user_id"
  end

  create_table "real_estate_monthly_volumes", force: :cascade do |t|
    t.bigint "county_market_stat_id", null: false
    t.date "period_date", null: false
    t.decimal "volume_amount", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["county_market_stat_id", "period_date"], name: "idx_volumes_county_period", unique: true
    t.index ["county_market_stat_id"], name: "index_real_estate_monthly_volumes_on_county_market_stat_id"
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
    t.string "stripe_payment_intent"
    t.integer "amount_cents"
    t.string "payment_status", default: "unpaid"
    t.string "provider_ref"
    t.string "download_url"
    t.index ["parcel_id"], name: "index_reports_on_parcel_id"
    t.index ["payment_status"], name: "idx_reports_payment_status"
    t.index ["stripe_payment_intent"], name: "idx_reports_stripe_pi", unique: true, where: "(stripe_payment_intent IS NOT NULL)"
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
    t.integer "price_cents"
    t.integer "credits_total", default: 0, null: false
    t.integer "credits_used", default: 0, null: false
    t.integer "credits_topup", default: 0, null: false
    t.integer "exports_limit", default: 0, null: false
    t.integer "exports_used", default: 0, null: false
    t.index ["status"], name: "idx_subscriptions_status"
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
    t.integer "records_synced", default: 0, null: false
    t.integer "records_failed", default: 0, null: false
    t.datetime "heartbeat_at"
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
    t.datetime "disabled_at"
    t.datetime "premium_disclaimer_accepted_at"
    t.integer "default_notify_days_before", default: 7, null: false
    t.boolean "email_notifications_enabled", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "viewed_parcels", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "parcel_id", null: false
    t.datetime "viewed_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "unlocked", default: false, null: false
    t.datetime "unlocked_at"
    t.integer "credits_spent", default: 0, null: false
    t.index ["parcel_id"], name: "index_viewed_parcels_on_parcel_id"
    t.index ["user_id", "parcel_id"], name: "idx_viewed_parcels_user_parcel", unique: true
    t.index ["user_id", "unlocked"], name: "idx_viewed_parcels_unlocked", where: "(unlocked = true)"
    t.index ["user_id"], name: "idx_vp_user_id_rls"
    t.index ["user_id"], name: "index_viewed_parcels_on_user_id"
  end

  add_foreign_key "admin_audit_logs", "users", column: "admin_user_id"
  add_foreign_key "admin_audit_logs", "users", column: "target_user_id"
  add_foreign_key "credit_topups", "users"
  add_foreign_key "credit_transactions", "parcels"
  add_foreign_key "credit_transactions", "users"
  add_foreign_key "export_logs", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "parcel_liens", "parcels"
  add_foreign_key "parcel_user_notes", "parcels"
  add_foreign_key "parcel_user_notes", "users"
  add_foreign_key "parcel_user_tags", "parcels"
  add_foreign_key "parcel_user_tags", "users"
  add_foreign_key "parcel_watches", "parcels"
  add_foreign_key "parcel_watches", "users"
  add_foreign_key "parcels", "auctions"
  add_foreign_key "pipeline_properties", "parcels", on_delete: :cascade
  add_foreign_key "pipeline_properties", "pipeline_stages", on_delete: :cascade
  add_foreign_key "pipeline_properties", "users", on_delete: :cascade
  add_foreign_key "pipeline_stages", "users", on_delete: :cascade
  add_foreign_key "real_estate_monthly_volumes", "county_market_stats"
  add_foreign_key "reports", "parcels"
  add_foreign_key "reports", "users"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "viewed_parcels", "parcels"
  add_foreign_key "viewed_parcels", "users"
end
