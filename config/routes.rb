# frozen_string_literal: true

Rails.application.routes.draw do
  root to: redirect("/users/sign_in")

  devise_for :users,
    controllers: { registrations: "registrations" }

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

  # Ruta temporal para subscripcion requerida
  get "subscription-required", to: "devise/sessions#new",
    as: :subscription_required
end