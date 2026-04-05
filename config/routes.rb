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
    resources :parcels,           only: [:index, :show]
    resources :auctions,          only: [:index, :show]
    resources :purchased_reports, only: [:index, :create]
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
      member do
        post :reset_usage
        post :cancel_subscription
      end
    end

    resources :reports, only: [:index, :show] do
      member do
        post  :retry
        patch :mark_failed
      end
    end

    resource :sync, only: [:show] do
      post :run_now
    end
  end

  # Webhooks de Stripe (endpoint publico, verificado por firma)
  namespace :stripe do
    post "webhooks", to: "webhooks#create"
  end

  # Healthcheck para Render
  get "/up", to: proc { [200, {}, ["OK"]] }
end