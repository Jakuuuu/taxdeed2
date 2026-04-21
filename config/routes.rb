# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users,
    controllers: { registrations: "registrations" }

  # Raiz apunta a la sesion de Devise sin loop
  devise_scope :user do
    root to: "devise/sessions#new"
  end

  # Pantalla de suscripcion inactiva (accesible sin autenticacion de Devise)
  get "subscription-required", to: "pages#subscription_required",
    as: :subscription_required

  # Investigacion privada (requiere subscripcion activa)
  namespace :research do
    resources :parcels, only: [:index, :show] do
      member do
        post :unlock            # POST /research/parcels/:id/unlock — Blur Paywall: consume 1 credit
      end
      collection do
        get :map_data           # GET /research/parcels/map_data.json
        get :county_overview    # GET /research/parcels/county_overview.json — Phase 1 county pins
        get :parcels_list       # GET /research/parcels/parcels_list.json — Phase 2 async parcel list
      end
    end

    # Mini CRM — Rama 2 escribe exclusivamente (nested under parcel context)
    resources :parcel_user_tags,  only: [:create],                   path: "parcel_user_tags"
    resources :parcel_user_notes, only: [:create, :destroy],         path: "parcel_user_notes"
    resources :auctions,          only: [:index, :show] do
      collection do
        get :jurisdictions  # AJAX: filtrado predictivo Estado → Jurisdicción
      end
    end
    resources :purchased_reports, only: [:index, :create]

    # ── Rama 4: Market Study ───────────────────────────────────────────────
    # Ficha de Condado: /research/market_study/counties
    # Regla: 18-market-study.md
    namespace :market_study do
      resources :counties, only: [:index, :show]
    end
    resource  :settings,          only: [:show] do
      patch  :profile
      delete :subscription, action: :cancel_subscription
    end
  end

  # Reportes: descarga y reintento
  resources :reports, only: [] do
    member do
      get  :download
      post :retry_report
    end
  end

  # ── Panel Admin (role admin: required) ─────────────────────────────────────
  namespace :admin do
    root to: "dashboard#index"

    resources :title_searches, only: [:index, :show, :update] do
      member do
        patch :mark_generated
        patch :mark_failed
      end
    end

    resources :auctions do
      member do
        patch :change_status
      end
      resources :parcels, only: [:index]
    end

    resources :users, only: [:index, :show] do
      collection do
        get :export_csv
      end
      member do
        post :reset_usage
        post :cancel_subscription
        post :toggle_admin
        post :toggle_disable
      end
    end

    resources :reports, only: [:index, :show] do
      member do
        post  :retry
        patch :mark_failed
      end
    end

    resource :sync, only: [:show], controller: "sync" do
      post :run_now
      post :run_markets
    end
  end

  # ── API interna (requiere autenticación) ──────────────────────────────────
  namespace :api do
    # Proxy server-side para Regrid tile server (oculta API token del frontend)
    get "regrid/tiles/:z/:x/:y", to: "regrid_tiles#show",
      constraints: { z: /\d+/, x: /\d+/, y: /\d+/ },
      as: :regrid_tile
    # Proxy server-side para Regrid parcel GeoJSON (oculta API token del frontend)
    # Consumido por show.html.erb — NUNCA interpolado en JS del cliente
    get "regrid/geojson", to: "regrid_tiles#geojson", as: :regrid_geojson
  end

  # Webhooks de Stripe (endpoint publico, verificado por firma)
  namespace :stripe do
    post "webhooks", to: "webhooks#create"
  end

  # Healthcheck para Render
  get "/up", to: proc { [200, {}, ["OK"]] }
end