# frozen_string_literal: true

# Server-to-server: the Rizz Speaker spends a browser's claim receipt (HTTP Basic client credentials).
class RizzAuth::ExchangesController < ActionController::API
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  before_action -> { response.headers["Cache-Control"] = "no-store" }
  rate_limit to: 120, within: 1.minute
  before_action :authenticate_client

  def create
    operation_id, receipt, rizz_sub, epoch = params.values_at(:operation_id, :receipt, :rizz_sub, :rizz_session_epoch)
    unless [ operation_id, receipt, rizz_sub ].all? { it.is_a?(String) && it.present? } && epoch.to_s.match?(/\A[1-9]\d{0,8}\z/)
      return render json: { error: "invalid_request" }, status: :bad_request
    end

    result = RizzSignIn::ClaimExchange.call(operation_id: operation_id, receipt: receipt, rizz_sub: rizz_sub, rizz_session_epoch: epoch.to_i)
    case result.status
    when :ok
      render json: {
        ok: true,
        local_handle: result.voter.handle.presence || RizzSignIn.mask_email(result.voter.email),
        has_independent_recovery: result.voter.confirmed?
      }
    when :conflict then render json: { error: "conflict" }, status: :conflict
    when :email_taken then render json: { error: "email_taken" }, status: :conflict
    else render json: { error: "invalid_receipt" }, status: :bad_request
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
