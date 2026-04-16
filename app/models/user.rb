# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :rememberable, :validatable
  # NOTE: :recoverable deshabilitado en M1 (requiere mailer)
  # Activar en fase posterior con SendGrid u otro provider

  # Virtual attribute — plan elegido en el formulario de registro.
  # No se persiste en users sino en subscriptions.
  attr_accessor :plan

  has_one  :subscription,       dependent: :destroy
  has_many :reports,            dependent: :destroy

  # ── Mini CRM ────────────────────────────────────────────────────────
  has_many :parcel_user_tags,   dependent: :destroy
  has_many :parcel_user_notes,  dependent: :destroy

  # ── Unlock / Viewed History ─────────────────────────────────────────
  has_many :viewed_parcels,     dependent: :destroy

  # ── Audit trail (as target) ─────────────────────────────────────────
  has_many :admin_audit_logs, foreign_key: :target_user_id, dependent: :destroy

  def full_name
    "#{first_name} #{last_name}".strip
  end

  def admin?
    admin
  end

  # ── Account disable ─────────────────────────────────────────────────
  # disabled_at = nil  → account active
  # disabled_at = Time → account locked out (Devise hook below)
  def disabled?
    disabled_at.present?
  end

  # Devise hook — block sign-in for disabled accounts.
  # Called automatically by Devise on every authentication attempt.
  def active_for_authentication?
    super && !disabled?
  end

  # Custom Devise message shown on login when account is disabled.
  def inactive_message
    disabled? ? :account_disabled : super
  end
end