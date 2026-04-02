# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users,
    controllers: { registrations: "registrations" }

  # Raiz apunta a la sesion de Devise sin loop (devise_scope evita require_no_authentication)
  devise_scope :user do
    root to: "devise/sessions#new"
    get "subscription-required", to: "devise/sessions#new",
      as: :subscription_required
  end

  # Investigacion privada (requiere subscripcion activa)
  namespace :research do
    resources :parcels, only: [:index, :show]
  end

  # Webhooks de Stripe (endpoint publico, verificado por firma)
  namespace :stripe do
    post "webhooks", to: "webhooks#create"
  end

  # Healthcheck para Render
  get "/up", to: proc { [200, {}, ["OK"]] }
end