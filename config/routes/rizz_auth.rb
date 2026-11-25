# frozen_string_literal: true

# Sign in with Rizz, the claim and create handoffs, and back-channel logout.
# Everything but back-channel logout is present only while RizzSignIn is enabled; back-channel logout stays mounted
# whenever Rizz is configured, so turning the feature off still ends Rizz-opened sessions.
# POST /auth/rizz/claim/google is the claim-only Google OmniAuth request path (see config/initializers/rizz_sign_in.rb).
constraints ->(_request) { RizzSignIn.enabled? } do
  post "auth/rizz", to: "rizz_auth/sessions#create", as: :rizz_auth
  get "auth/rizz/callback", to: "rizz_auth/sessions#callback", as: :rizz_auth_callback
  post "auth/rizz/claim/start", to: "rizz_auth/claims#start", as: :rizz_claim_start
  get "auth/rizz/claim/prove", to: "rizz_auth/claims#prove", as: :rizz_claim_prove
  post "auth/rizz/claim/verify_password", to: "rizz_auth/claims#verify_password", as: :rizz_claim_verify_password
  get "auth/rizz/claim/google/callback", to: "rizz_auth/claims#google_callback", as: :rizz_claim_google_callback
  get "auth/rizz/claim/confirm", to: "rizz_auth/claims#confirm", as: :rizz_claim_confirm
  post "auth/rizz/claim/confirm", to: "rizz_auth/claims#connect"
  post "auth/rizz/claim/cancel", to: "rizz_auth/claims#cancel", as: :rizz_claim_cancel
  post "auth/rizz/create/start", to: "rizz_auth/creations#start", as: :rizz_create_start
  get "auth/rizz/create", to: "rizz_auth/creations#new", as: :rizz_create
  post "auth/rizz/create", to: "rizz_auth/creations#create"
  post "auth/rizz/create/cancel", to: "rizz_auth/creations#cancel", as: :rizz_create_cancel
  post "auth/rizz/claim/exchange", to: "rizz_auth/exchanges#create"
  post "auth/rizz/usernames/check", to: "rizz_auth/usernames#check"
end

constraints ->(_request) { RizzSignIn.configuration.configured? } do
  post "auth/rizz/backchannel_logout", to: "rizz_auth/backchannel_logouts#create"
end
