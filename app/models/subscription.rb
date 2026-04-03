# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :user

  PLAN_LIMITS = {
    "standard" => { parcels: 500,   avm: 15,  scope: 2,  title: 0, annual_cents: 49700 },
    "pro"      => { parcels: 2500,  avm: 50,  scope: 10, title: 1, annual_cents: 69700 },
    "premier"  => { parcels: 10000, avm: 200, scope: 60, title: 1, annual_cents: 399700 }
  }.freeze

  TRIAL_LIMITS = { parcels: 10, avm: 0, scope: 0, title: 0 }.freeze

  # ── Status ─────────────────────────────────────────────────────
  def active_or_trial?
    status.in?(%w[trial active])
  end

  def trial?   = status == "trial"
  def active?  = status == "active"
  def past_due? = status == "past_due"

  # ── Usage checks ───────────────────────────────────────────────
  def can_use?(type)
    return false unless active_or_trial?
    if type == :title
      # Title Search is a one-time lifetime bonus
      limit_title > 0 && !title_search_used?
    else
      send("used_#{type}") < send("limit_#{type}")
    end
  end

  def usage_percent(type)
    return (title_search_used? ? 100 : 0) if type == :title
    limit = send("limit_#{type}")
    return 0 if limit.zero?
    (send("used_#{type}").to_f / limit * 100).round
  end

  # Returns :ok; raises on failure
  def increment_usage!(type)
    if type == :title
      with_lock do
        raise "Title Search has already been used." if title_search_used?
        update!(title_search_used: true)
      end
    else
      with_lock do
        raise "Credit limit reached" unless can_use?(type)
        increment!("used_#{type}")
      end
    end
    :ok
  end


  # ── Plans ──────────────────────────────────────────────────────
  def apply_plan_limits!
    limits = PLAN_LIMITS.fetch(plan_name, PLAN_LIMITS["standard"])
    update!(
      limit_parcels:       limits[:parcels],
      limit_avm:           limits[:avm],
      limit_scope:         limits[:scope],
      limit_title:         limits[:title],
      annual_amount_cents: limits[:annual_cents]
    )
  end

  def plan_label
    plan_name&.capitalize || "Standard"
  end

  # ── Billing helpers ────────────────────────────────────────────
  def annual_amount_dollars
    return 0 unless annual_amount_cents
    annual_amount_cents / 100.0
  end

  def next_reset_date
    current_period_end || (created_at + 1.year)
  end
end