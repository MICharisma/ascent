# frozen_string_literal: true

# Claim-only Google proof: a second Google OmniAuth strategy on its own paths, so Devise's normal Google
# sign-in (Voters::OmniauthCallbacksController, Voter.from_google) never handles a claim. Consumer Google OAuth
# does not support max_age=0 or reliably emit auth_time, so we enforce an explicit account chooser
# (prompt=select_account) that cannot be overridden from the request, and pair it with fresh ID token
# issuance (iat), browser-bound __Host-rizz_claim_local, strict Google uid lookup, and dual-identity confirmation.
require "rizz_auth/omniauth/rizz_claim_google"

google_client_id = ENV.fetch("GOOGLE_CLIENT_ID") { Rails.application.credentials.dig(:google, :client_id) }
google_client_secret = ENV.fetch("GOOGLE_CLIENT_SECRET") { Rails.application.credentials.dig(:google, :client_secret) }
if (google_client_id.blank? || google_client_secret.blank?) && Rails.env.test?
  google_client_id = "test-client-id"
  google_client_secret = "test-client-secret"
end

Rails.application.config.middleware.use OmniAuth::Strategies::RizzClaimGoogle, google_client_id, google_client_secret,
  **RizzAuth::OmniAuth::RizzClaimGoogle.middleware_options(enabled_check: -> { RizzSignIn.enabled? && RizzSignIn.google_proof_enabled? })

Rails.application.config.after_initialize do
  require "devise/omniauth"
  devise_failure = OmniAuth.config.on_failure
  OmniAuth.config.on_failure = proc do |env|
    if env["PATH_INFO"].to_s.start_with?("/auth/rizz/claim/google")
      RizzAuth::ClaimsController.action(:google_failure).call(env)
    else
      devise_failure.call(env)
    end
  end
end

# A session opened by Sign in with Rizz ends once the feature is switched off, its binding is disconnected, or
# its Rizz epoch is behind the binding's (back-channel logout). The marker is written only by the Rizz callback
# (an :authentication event); any other sign-in (password, Google, remember-me) clears it first, so a stale
# marker can never log a different sign-in out.
RizzAuth::WardenHook.install!(
  scope: :voter,
  enabled: -> { RizzSignIn.enabled? },
  binding_lookup: ->(binding_id, voter) {
    status, epoch, voter_id = VoterRizzBinding.where(id: binding_id).pick(:status, :rizz_session_epoch, :voter_id)
    { active: status == "active" && voter_id == voter.id, epoch: epoch }
  },
  remember_cookie: :remember_voter_token
)
