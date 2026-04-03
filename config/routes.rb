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
    resources :parcels, only: [:index, :show]
    resources :auctions, only: [:index]
    resources :purchased_reports, only: [:index]
  end

  # Webhooks de Stripe (endpoint publico, verificado por firma)
  namespace :stripe do
    post "webhooks", to: "webhooks#create"
  end

  # Healthcheck para Render
  get "/up", to: proc { [200, {}, ["OK"]] }
end