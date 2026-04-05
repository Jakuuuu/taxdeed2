# frozen_string_literal: true

# Admin::BaseController
# Controlador base para el panel admin. Requiere autenticación y rol admin.
module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    before_action :set_nav_counts

    layout "admin"  # usará layouts/admin.html.erb si existe, si no hereda de application

    private

    def require_admin!
      unless current_user.admin?
        redirect_to research_parcels_path, alert: "Acceso restringido."
      end
    end

    # Poblado aquí para que el layout sidebar no ejecute queries directos
    def set_nav_counts
      @nav_pending_title_searches = Report.title_search.where(status: :ordered).count
    end
  end
end
