# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :rememberable, :validatable
  # NOTE: :recoverable deshabilitado en M1 (requiere mailer)
  # Activar en fase posterior con SendGrid u otro provider

  # Virtual attribute — plan elegido en el formulario de registro.
  # No se persiste en users sino en subscriptions.
  attr_accessor :plan

  has_one :subscription, dependent: :destroy

  def full_name
    "#{first_name} #{last_name}".strip
  end

  def admin?
    admin
  end
end