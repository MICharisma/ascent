# frozen_string_literal: true

# Anti-phishing claim: the Speaker hands the browser here with a signed handoff; the browser must prove it
# controls a local Voter (fresh password or fresh claim-only Google), see both the Voter and the requesting
# Speaker, and confirm before a single-use receipt is minted for the Speaker's server-to-server exchange.
class RizzAuth::ClaimsController < ApplicationController
  include RizzAuth::CookieHelper

  COOKIE = "rizz_claim_local"

  def self.dummy_password_digest
    @dummy_password_digest ||= Devise::Encryptor.digest(Voter, SecureRandom.hex(16))
  end

  skip_before_action :authorize_action_policy_resource!
  skip_verify_authorized
  skip_forgery_protection only: %i[start google_failure] # start is entered from the Speaker; its JWT is the credential
  before_action -> { response.headers["Cache-Control"] = "no-store" }
  content_security_policy { |policy| policy.frame_ancestors :none }
  before_action :load_handoff, except: %i[start google_failure]
  before_action :require_proof, only: %i[confirm connect]
  rate_limit to: 20, within: 1.minute, only: %i[start connect],
    with: -> { claim_rejected "Too many attempts. Try again in a minute." }
  rate_limit to: 10, within: 3.minutes, only: :verify_password,
    with: -> { redirect_to rizz_claim_prove_path, status: :see_other, alert: "Too many attempts. Try again in a few minutes." }

  helper_method :masked_email, :google_proof_enabled?

  def start
    claims = RizzSignIn::TokenVerifier.verify_claim_handoff(params[:handoff])
    return claim_rejected unless RizzClaimHandoff.acceptable?(claims)

    handoff, token = RizzClaimHandoff.start!(claims)
    delete_rizz_cookie RizzAuth::CreationsController::COOKIE # a browser never holds both flows' cookies
    write_rizz_cookie COOKIE, { "handoff_id" => handoff.id, "token" => token }, expires_in: RizzClaimHandoff::LIFETIME
    redirect_to rizz_claim_prove_path, status: :see_other
  rescue RizzSignIn::InvalidToken, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    claim_rejected
  rescue RizzSignIn::Unavailable
    claim_rejected "Rizz is unavailable right now. Please try again from Rizz."
  end

  def prove
    @signed_in_voter = current_voter
  end

  def verify_password
    password = params[:password]
    voter = Voter.find_for_database_authentication(email: params[:email].to_s.strip.downcase) if password.is_a?(String)
    Devise::Encryptor.compare(Voter, self.class.dummy_password_digest, password) if voter.nil? && password.is_a?(String)
    return prove_failed "That email and password didn't match." unless voter&.valid_password?(password) && claimable?(voter)

    proven = @handoff.with_lock do
      next false unless @handoff.claim_intent? && @handoff.usable?

      @handoff.prove!(voter)
      true
    end
    return claim_rejected unless proven

    redirect_to rizz_claim_confirm_path, status: :see_other
  end

  # OmniAuth (the claim-only Google strategy, never Devise's) lands here. Only a Voter already linked to this
  # Google subject counts; no email matching and no account creation. A browser in the Create flow reuses this
  # callback to optionally prove its Google account (see #create_google_callback).
  def google_callback
    auth = request.env["omniauth.auth"]
    uid = RizzAuth::GoogleProof.verified_uid(auth)
    return create_google_callback(auth, uid) if @create_flow

    voter = Voter.find_by_google_uid(uid) if uid
    return prove_failed "Google couldn't confirm an account linked to Ascent. Try picking the linked Google account or use your password instead." unless voter
    return prove_failed "That account can't be connected right now." unless claimable?(voter)

    proven = @handoff.with_lock do
      next false unless @handoff.claim_intent? && @handoff.usable?

      @handoff.prove!(voter)
      true
    end
    return claim_rejected unless proven

    redirect_to rizz_claim_confirm_path, status: :see_other
  end

  def google_failure
    message = "Google sign-in was cancelled or could not be completed."
    if cookie_handoff(COOKIE)&.claim_intent? || !cookie_handoff(RizzAuth::CreationsController::COOKIE)&.create_intent?
      redirect_to rizz_claim_prove_path, status: :see_other, alert: message
    else
      redirect_to rizz_create_path, status: :see_other, alert: message
    end
  end

  def confirm
    @voter = @handoff.verified_voter
  end

  def connect
    receipt = nil
    @handoff.with_lock do
      voter = @handoff.verified_voter
      next unless @handoff.claim_intent? && @handoff.usable? && @handoff.proven? && claimable?(voter) &&
        RizzSignIn.configuration.issuer_origin?(@handoff.callback_uri) && @handoff.consume!

      receipt = RizzClaimReceipt.issue!(voter: voter, operation_id: @handoff.operation_id)
    end
    return claim_rejected unless receipt

    delete_rizz_cookie COOKIE
    redirect_to @handoff.return_url(receipt), allow_other_host: true, status: :see_other
  rescue ActiveRecord::RecordNotUnique
    claim_rejected
  end

  def cancel
    @handoff.consume!
    delete_rizz_cookie COOKIE
    redirect_to root_path, status: :see_other, notice: "Nothing was connected."
  end

  private

  # The Claim cookie first. Only the Google callback also accepts the Create cookie, for the optional "Link Google now".
  def load_handoff
    if (handoff = cookie_handoff(COOKIE))&.claim_intent?
      @handoff = handoff
    elsif action_name == "google_callback" && (handoff = cookie_handoff(RizzAuth::CreationsController::COOKIE))&.create_intent?
      @handoff = handoff
      @create_flow = true
    else
      claim_rejected "This connect link expired or was opened in a different browser. Start again from Rizz."
    end
  end

  # The usable handoff whose browser token matches the named cookie, whatever its intent.
  def cookie_handoff(cookie)
    data = read_rizz_cookie(cookie)
    handoff = RizzClaimHandoff.find_by(id: data["handoff_id"]) if data.is_a?(Hash) && data["token"].is_a?(String)
    return unless handoff&.usable?

    handoff if ActiveSupport::SecurityUtils.secure_compare(handoff.browser_token_digest, RizzClaimHandoff.digest(data["token"]))
  end

  # Create flow: Google only proves control of the verified email's Google account so it can be linked once the
  # Voter is created. It never signs in, links by email, calls Voter.from_google, or creates a Voter.
  def create_google_callback(auth, uid)
    unless uid && auth.dig("info", "email_verified") == true
      return create_google_rejected "Google couldn't verify that account. Try again, or create your account without linking Google now."
    end

    google_email = auth.dig("info", "email").to_s.strip.downcase
    handoff_email = nil
    outcome = @handoff.with_lock do
      next :gone unless @handoff.create_intent? && @handoff.usable?

      handoff_email = @handoff.email
      next :email_mismatch unless google_email == handoff_email

      if Voter.find_by_google_uid(uid).present?
        @handoff.switch_to_claim!
        :existing_voter
      else
        @handoff.update!(google_uid: uid)
        :attached
      end
    end

    case outcome
    when :gone
      claim_rejected
    when :email_mismatch
      create_google_rejected "Choose the Google account matching #{masked_email(handoff_email)}, or create your account without linking Google now."
    when :existing_voter
      token = read_rizz_cookie(RizzAuth::CreationsController::COOKIE)["token"]
      delete_rizz_cookie RizzAuth::CreationsController::COOKIE
      write_rizz_cookie COOKIE, { "handoff_id" => @handoff.id, "token" => token }, expires_in: RizzClaimHandoff::LIFETIME
      redirect_to rizz_claim_prove_path, status: :see_other,
        notice: "That Google account already belongs to an Ascent account. Confirm it's you to connect it."
    when :attached
      redirect_to rizz_create_path, status: :see_other,
        notice: "Google account verified and will be linked when you create your account."
    end
  end

  def create_google_rejected(message)
    redirect_to rizz_create_path, status: :see_other, alert: message
  end

  def require_proof
    return if @handoff.proven? && claimable?(@handoff.verified_voter)

    redirect_to rizz_claim_prove_path, status: :see_other, alert: "Confirm it's you before connecting."
  end

  def claimable?(voter)
    voter.present? && voter.active_for_authentication?
  end

  def prove_failed(message)
    redirect_to rizz_claim_prove_path, status: :see_other, alert: message
  end

  def claim_rejected(message = "That connect link isn't valid. Start again from Rizz.")
    redirect_to new_voter_session_path, status: :see_other, alert: message
  end

  def google_proof_enabled?
    RizzSignIn.google_proof_enabled?
  end

  def masked_email(email)
    RizzSignIn.mask_email(email)
  end
end
