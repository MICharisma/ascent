# frozen_string_literal: true

class RizzAuth::SessionsController < ApplicationController
  include RizzAuth::CookieHelper

  FLOW_COOKIE = "rizz_auth_flow"

  skip_before_action :authorize_action_policy_resource!
  skip_verify_authorized
  before_action -> { response.headers["Cache-Control"] = "no-store" }
  content_security_policy { |policy| policy.frame_ancestors :none }
  rate_limit to: 10, within: 1.minute, only: %i[create callback],
    with: -> { rizz_failed "Too many Rizz sign-in attempts. Try again in a minute." }

  def create
    verifier = SecureRandom.urlsafe_base64(48)
    flow = { "state" => SecureRandom.urlsafe_base64(32), "nonce" => SecureRandom.urlsafe_base64(32), "verifier" => verifier }
    write_rizz_cookie FLOW_COOKIE, flow, expires_in: 10.minutes
    redirect_to RizzSignIn::Client.authorization_url(
      redirect_uri: rizz_auth_callback_url,
      state: flow["state"],
      nonce: flow["nonce"],
      code_challenge: RizzSignIn::Client.code_challenge(verifier)
    ), allow_other_host: true, status: :see_other
  rescue RizzSignIn::Error
    rizz_failed "Rizz is unavailable right now. Please try again."
  end

  def callback
    flow = read_rizz_cookie(FLOW_COOKIE)
    delete_rizz_cookie FLOW_COOKIE
    unless flow.is_a?(Hash) && params[:error].blank? && params[:code].is_a?(String) && params[:state].is_a?(String) &&
        ActiveSupport::SecurityUtils.secure_compare(params[:state], flow["state"].to_s)
      return rizz_failed
    end

    id_token = RizzSignIn::Client.exchange_code(
      code: params[:code],
      code_verifier: flow["verifier"],
      redirect_uri: rizz_auth_callback_url
    )
    claims = RizzSignIn::TokenVerifier.verify_id_token(id_token, nonce: flow["nonce"])
    binding = VoterRizzBinding.active.find_by(rizz_sub: claims["sub"])
    unless binding
      return redirect_to new_voter_session_path, status: :see_other,
        notice: "That Rizz account isn't connected to an Ascent account yet. Connect it from Rizz, or sign in another way."
    end

    voter = nil
    outcome = binding.with_lock do
      next :rejected unless binding.active? && claims["rizz_epoch"] >= binding.rizz_session_epoch

      voter = binding.voter
      next :inactive unless voter.active_for_authentication?

      binding.update!(rizz_session_epoch: claims["rizz_epoch"]) if claims["rizz_epoch"] > binding.rizz_session_epoch
      :ok
    end
    return rizz_failed "Your account can't sign in right now." if outcome == :inactive
    return rizz_failed unless outcome == :ok

    sign_in :voter, voter, event: :authentication, force: true
    cookies.delete(:remember_voter_token)
    session["rizz_binding_id"] = binding.id
    session["rizz_session_epoch"] = binding.rizz_session_epoch
    redirect_to after_sign_in_path_for(voter), status: :see_other
  rescue RizzSignIn::Unavailable
    rizz_failed "Rizz is unavailable right now. Please try again."
  rescue RizzSignIn::Error
    rizz_failed
  end

  private

  def rizz_failed(message = "Rizz sign-in could not be completed. Please try again.")
    redirect_to new_voter_session_path, status: :see_other, alert: message
  end
end
