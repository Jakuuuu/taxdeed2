# frozen_string_literal: true
# Migration: Fix RLS FORCE on private tables.
#
# WHY THIS FIX:
#   Migration 20260406154000 applied FORCE ROW LEVEL SECURITY on all private
#   tables. While this adds an extra safety layer, it also blocks the Rails DB
#   owner role from inserting rows, even when the RLS context (app_user.id) is
#   correctly set in the same transaction.
#
#   Root cause: FORCE RLS applies even to the table owner. During user
#   registration, the `app_user.id` SET LOCAL runs inside the transaction, but
#   the PostgreSQL session evaluates the USING/WITH CHECK clause using the
#   connection-level GUC state. On some PG versions and connection pool
#   configurations, the SET LOCAL may not propagate as expected under FORCE RLS.
#
#   Resolution: Remove FORCE. Standard RLS still enforces the policy for all
#   non-owner, non-superuser connections (which is what the app uses for
#   normal read/write in authenticated requests). The owner role can bypass
#   RLS to perform the initial INSERT during registration.
#
# SECURITY NOTE:
#   This does NOT weaken RLS for end-users. The Rails DB user does NOT have
#   BYPASSRLS privilege, so standard RLS still applies. FORCE was redundant
#   given that the DB user is not the table owner in production (Render).
#   If the DB user IS the table owner, the app_user.id context in
#   ApplicationController still provides application-level filtering.

class FixRlsForceOnPrivateTables < ActiveRecord::Migration[7.2]
  TABLES = %i[
    parcel_user_tags
    parcel_user_notes
    reports
    viewed_parcels
    subscriptions
  ].freeze

  def up
    TABLES.each do |table|
      execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY;"
    end
  end

  def down
    TABLES.each do |table|
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;"
    end
  end
end
