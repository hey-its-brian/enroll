# frozen_string_literal: true

class SessionTimeoutController < ApplicationController
  # These are what prevent check_time_until_logout and
  # reset_user_clock from resetting users' Timeoutable
  # Devise "timers"
  prepend_before_action :skip_timeout, only: [:check_time_until_logout, :has_user_timed_out]

  def skip_timeout
    request.env["devise.skip_trackable"] = true
  end

  skip_before_action :authenticate_user!, only: [:has_user_timed_out], raise: false

  def check_time_until_logout
    return handle_expired_session if user_session.nil? || user_session["last_request_at"].nil?

    begin
      last_request_time = user_session["last_request_at"]
      last_request_time = Time.parse(last_request_time) if last_request_time.is_a?(String)

      @time_left = [Devise.timeout_in - (Time.now - last_request_time).to_i, 0].max
      @bs4 = params[:bs4] == "true"

      respond_to do |format|
        if @time_left <= 0
          handle_expired_session
        else
          format.js { render 'devise/sessions/session_expiration_warning' }
          format.json { render json: { expired: false, time_left: @time_left } }
        end
      end
    rescue StandardError => e
      Rails.logger.error "Error calculating session timeout: #{e.message}"
      handle_expired_session
    end
  end

  def reset_user_clock
    user_session["last_request_at"] = Time.now if user_session

    respond_to do |format|
      format.js { head :ok }
      format.json { render json: { success: true } }
    end
  end

  private

  def handle_expired_session
    sign_out(current_user) if current_user

    respond_to do |format|
      format.js { render 'devise/sessions/sign_out_user' }
      format.json { render json: { expired: true } }
    end
  end
end