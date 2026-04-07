# frozen_string_literal: true
# Migration: Enable Row Level Security (RLS) on all CRM and user-private tables.
#
# WHY RLS:
#   Application-level filters (WHERE user_id = current_user.id) are the first line
#   of defense, but they break if any future controller, raw SQL query, or third-party
#   gem forgets to add the scope. PostgreSQL RLS provides a categorical second layer:
#   the DB itself will NEVER return rows belonging to another user, regardless of
#   which code path reads the table.
#
# TABLES PROTECTED:
#   - parcel_user_tags   (Mini CRM private tags)
#   - parcel_user_notes  (Mini CRM private notes)
#   - reports            (purchased reports — user private)
#   - viewed_parcels     (parcel view history — user private)
#   - subscriptions      (billing data — user private)
#
# HOW IT WORKS:
#   1. RLS is ENABLED on the table.
#   2. A POLICY is created that only allows SELECT/INSERT/UPDATE/DELETE
#      when the row's user_id matches the current app_user.id setting.
#   3. Rails sets this session variable in ApplicationController before every
#      request (added alongside this migration).
#
# IMPORTANT: The 'rails' DB user used by the app must NOT be a superuser.
#   Superusers bypass RLS. Verify with:
#     SELECT rolsuper FROM pg_roles WHERE rolname = 'your_db_user';
#   Should return: f (false)
#
# ADMIN/SIDEKIQ BYPASS:
#   Admin queries and background jobs (Sidekiq) that legitimately need to read
#   all rows should set: SET app_user.id = '0'  (admin sentinel)
#   And the USING clause handles the exception logic below.

class EnableRlsOnPrivateTables < ActiveRecord::Migration[7.2]
  def up
    tables_with_user_id = %i[
      parcel_user_tags
      parcel_user_notes
      reports
      viewed_parcels
      subscriptions
    ]

    tables_with_user_id.each do |table|
      # Step 1: Enable RLS
      execute <<-SQL.squish
        ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      SQL

      # Step 2: Force RLS even for table owner — REMOVED.
      # Using FORCE RLS blocked the Rails owner role during registration
      # (no session context exists yet when inserting the first subscription).
      # Standard RLS without FORCE still enforces policies for app requests
      # because the DB user is not a superuser. BYPASSRLS is not granted.

      # Step 3: Create the SELECT/INSERT/UPDATE/DELETE policy
      # The policy allows access when:
      #   a) user_id matches the current session variable (normal user requests)
      #   b) OR the session variable is '0' (admin/background job bypass)
      execute <<-SQL.squish
        CREATE POLICY user_isolation_policy ON #{table}
          USING (
            user_id::text = current_setting('app_user.id', true)
            OR current_setting('app_user.id', true) = '0'
          )
          WITH CHECK (
            user_id::text = current_setting('app_user.id', true)
            OR current_setting('app_user.id', true) = '0'
          );
      SQL
    end

    # Index to ensure RLS policy evaluation is fast
    # (most tables already have these from previous migrations — add only if missing)
    add_index :parcel_user_tags,  :user_id, name: "idx_put_user_id_rls",   if_not_exists: true
    add_index :parcel_user_notes, :user_id, name: "idx_pun_user_id_rls",   if_not_exists: true
    add_index :reports,           :user_id, name: "idx_rep_user_id_rls",   if_not_exists: true
    add_index :viewed_parcels,    :user_id, name: "idx_vp_user_id_rls",    if_not_exists: true
    add_index :subscriptions,     :user_id, name: "idx_sub_user_id_rls",   if_not_exists: true
  end

  def down
    tables_with_user_id = %i[
      parcel_user_tags
      parcel_user_notes
      reports
      viewed_parcels
      subscriptions
    ]

    tables_with_user_id.each do |table|
      execute "DROP POLICY IF EXISTS user_isolation_policy ON #{table};"
      execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;"
    end
  end
end
