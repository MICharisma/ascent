# frozen_string_literal: true

# Server-to-server: Rizz checks whether a candidate handle is available on Ascent (HTTP Basic client credentials).
class RizzAuth::UsernamesController < ActionController::API
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  USERNAME_FORMAT = /\A[a-z0-9_]{3,24}\z/

  before_action -> { response.headers["Cache-Control"] = "no-store" }
  rate_limit to: 120, within: 1.minute
  before_action :authenticate_client

  def check
    raw = params[:username]
    unless raw.is_a?(String)
      return render json: { username: "", status: "invalid", available: false }, status: :unprocessable_content
    end

    username = raw.strip.downcase
    unless USERNAME_FORMAT.match?(username)
      return render json: { username: username, status: "invalid", available: false }, status: :unprocessable_content
    end

    if Voter::RESERVED_USERNAMES.include?(username)
      render json: { username: username, status: "reserved", available: false }, status: :ok
    elsif Voter.where("LOWER(username) = ?", username).exists?
      render json: { username: username, status: "taken", available: false }, status: :ok
    else
      render json: { username: username, status: "available", available: true }, status: :ok
    end
  end

  private

  def authenticate_client
    configuration = RizzSignIn.configuration
    authenticate_or_request_with_http_basic("Rizz") do |client_id, client_secret|
      configuration.valid_exchange_credentials?(client_id, client_secret)
    end
  end
end
