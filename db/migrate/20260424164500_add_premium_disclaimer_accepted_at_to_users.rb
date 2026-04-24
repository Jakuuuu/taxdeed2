# frozen_string_literal: true

# ══════════════════════════════════════════════════════════════════════════════
# Migration: Gated Disclaimer — Audit Trail
# ══════════════════════════════════════════════════════════════════════════════
# Adds premium_disclaimer_accepted_at (datetime) to users table.
#
# Business Rule:
#   The user MUST explicitly accept the legal disclaimer before viewing any
#   premium (unlocked) property data. This field records the timestamp of
#   that acceptance as an immutable legal audit trail.
#
# Architecture Decision:
#   Global per-user (NOT per-parcel) — the user signs once, and that acceptance
#   covers all future premium data views. This avoids friction on every unlock.
#
# NULL semantics:
#   NULL  → user has NOT accepted the disclaimer yet → overlay blocks view
#   !NULL → user accepted on that timestamp → premium data visible
# ══════════════════════════════════════════════════════════════════════════════
class AddPremiumDisclaimerAcceptedAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :premium_disclaimer_accepted_at, :datetime, null: true, default: nil
  end
end
