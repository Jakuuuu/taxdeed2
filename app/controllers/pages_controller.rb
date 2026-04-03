# frozen_string_literal: true

class PagesController < ApplicationController
  # No requiere autenticacion — es la pantalla a la que se redirige
  # cuando la suscripcion esta inactiva o cancelada
  skip_before_action :authenticate_user!

  def subscription_required
    # Si el usuario esta autenticado y su suscripcion esta activa,
    # redirigir directamente al dashboard
    if user_signed_in? && current_user.subscription&.active_or_trial?
      redirect_to research_parcels_path
    end
  end
end
