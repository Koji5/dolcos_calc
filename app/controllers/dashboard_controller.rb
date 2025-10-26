class DashboardController < ApplicationController
  before_action :authenticate_user!
  def show
    render layout: false if turbo_frame_request?
  end
end
