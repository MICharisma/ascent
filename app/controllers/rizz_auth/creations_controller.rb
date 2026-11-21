# frozen_string_literal: true

# Account creation from the Rizz Speaker: it hands the browser here with a signed handoff carrying a verified
# Google email. The browser chooses a name, username, display name and optional local password; nothing is created
# in Ascent until the Speaker spends the receipt (RizzSignIn::ClaimExchange). An email that already has a Voter
# continues as an ordinary Claim, which this controller never proves, links or modifies.
class RizzAuth::CreationsController < ApplicationController
  include RizzAuth::CookieHelper

  COOKIE = "rizz_create_local"

  skip_before_action :authorize_action_policy_resource!
  skip_verify_authorized
  skip_forgery_protection only: :start # start is entered from the Speaker; its JWT is the credential
  before_action -> { response.headers["Cache-Control"] = "no-store" }
  content_security_policy { |policy| policy.frame_ancestors :none }
  before_action :load_handoff, except: :start
  before_action :load_signed_in_voter, only: %i[new create]
  rate_limit to: 20, within: 1.minute, only: :start,
    with: -> { create_rejected "Too many attempts. Try again in a minute." }
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to rizz_create_path, status: :see_other, alert: "Too many attempts. Try again in a few minutes." }

  helper_method :minimum_password_length, :google_proof_enabled?

  def start
    claims = RizzSignIn::TokenVerifier.verify_create_handoff(params[:handoff])
    return create_rejected unless RizzClaimHandoff.acceptable?(claims)

    RizzClaimHandoff.purge_spent_drafts!
    expires_at = Time.zone.at(claims.fetch("exp"))
    if Voter.exists?(email: claims["email"])
      handoff, token = RizzClaimHandoff.start!(claims, expires_at: expires_at)
      continue_as_claim handoff, token
    else
      handoff, token = RizzClaimHandoff.start!(claims, intent: "create", expires_at: expires_at)
      delete_rizz_cookie RizzAuth::ClaimsController::COOKIE # a browser never holds both flows' cookies
      write_rizz_cookie COOKIE, { "handoff_id" => handoff.id, "token" => token }, expires_in: RizzClaimHandoff::LIFETIME
      redirect_to rizz_create_path, status: :see_other
    end
  rescue RizzSignIn::InvalidToken, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    create_rejected
  rescue RizzSignIn::Unavailable
    create_rejected "Rizz is unavailable right now. Please try again from Rizz."
  end

  def new
    suggested_first_name, suggested_last_name = @handoff.suggested_name_parts
    @voter = Voter.new(
      first_name: @handoff.first_name.presence || suggested_first_name.presence,
      last_name: @handoff.last_name.presence || suggested_last_name.presence,
      username: @handoff.username.presence || @handoff.suggested_username,
      display_name: @handoff.display_name
    )
    @suggested_username_taken = @voter.username.present? &&
      (Voter::RESERVED_USERNAMES.include?(@voter.username.downcase) || Voter.where("LOWER(username) = ?", @voter.username.downcase).exists?)
  end

  def create
    result = RizzSignIn::Onboarding.call(handoff: @handoff, attributes: voter_params)
    case result.status
    when :onboarded
      delete_rizz_cookie COOKIE
      redirect_to @handoff.return_url(result.receipt), allow_other_host: true, status: :see_other
    when :invalid
      @voter = result.voter
      render :new, status: :unprocessable_content
    when :existing_email
      continue_as_claim @handoff, @browser_token
    else
      create_rejected "This link expired or was already used. Start again from Rizz."
    end
  end

  def cancel
    @handoff.cancel_create!
    delete_rizz_cookie COOKIE
    redirect_to root_path, status: :see_other, notice: "Nothing was created."
  end

  private

  def load_handoff
    data = read_rizz_cookie(COOKIE)
    handoff = RizzClaimHandoff.find_by(id: data["handoff_id"]) if data.is_a?(Hash) && data["token"].is_a?(String)
    if handoff&.create_intent? && handoff.usable? &&
        ActiveSupport::SecurityUtils.secure_compare(handoff.browser_token_digest, RizzClaimHandoff.digest(data["token"]))
      @handoff = handoff
      @browser_token = data["token"]
    else
      create_rejected "This link expired or was opened in a different browser. Start again from Rizz."
    end
  end

  def load_signed_in_voter
    @signed_in_voter = current_voter
  end

  # The password fields are optional: both blank (or omitted) means a passwordless create.
  def voter_params
    params.expect(voter: %i[first_name last_name username display_name password password_confirmation])
      .to_h.with_defaults("password" => "", "password_confirmation" => "")
  end

  # The handoff is now an ordinary claim handoff, so hand the browser to the Claim proof with its own cookie.
  def continue_as_claim(handoff, token)
    delete_rizz_cookie COOKIE
    write_rizz_cookie RizzAuth::ClaimsController::COOKIE, { "handoff_id" => handoff.id, "token" => token }, expires_in: RizzClaimHandoff::LIFETIME
    redirect_to rizz_claim_prove_path, status: :see_other,
      notice: "That email already has an Ascent account. Confirm it's you to connect it."
  end

  def create_rejected(message = "That link isn't valid. Start again from Rizz.")
    redirect_to new_voter_session_path, status: :see_other, alert: message
  end

  def google_proof_enabled?
    RizzSignIn.google_proof_enabled?
  end

  def minimum_password_length
    Devise.password_length.min
  end
end
