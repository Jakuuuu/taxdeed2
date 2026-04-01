# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :user

  PLAN_LIMITS = {
    "standard" => { parcels: 500,   avm: 15,  scope: 2,  title: 0, annual_cents: 49700 },
    "pro"      => { parcels: 2500,  avm: 50,  scope: 10, title: 1, annual_cents: 69700 },
    "premier"  => { parcels: 10000, avm: 200, scope: 60, title: 1, annual_cents: 399700 }
  }.freeze

  TRIAL_LIMITS = { parcels: 10, avm: 0, scope: 0, title: 0 }.freeze

  def active_or_trial?
    status.in?(%w[trial active])
  end

  def can_use?(type)
    return false unless active_or_trial?
    send("used_#{type}") < send("limit_#{type}")
  end

  def usage_percent(type)
    limit = send("limit_#{type}")
    return 0 if limit.zero?
    (send("used_#{type}").to_f / limit * 100).round
  end

  # Aplicar limites del plan al crear/cambiar plan
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
end