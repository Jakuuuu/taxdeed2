# frozen_string_literal: true

module Research
  class BaseController < ApplicationController
    before_action :require_active_subscription!

    layout "research"
  end
end
