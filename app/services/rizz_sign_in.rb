# frozen_string_literal: true

# Sign in with Rizz (OIDC authorization code + S256 PKCE, ID token only) and the
# claim/back-channel-logout endpoints that connect a Voter to a Rizz subject.
# Everything is off unless RIZZ_SIGN_IN_ENABLED=1 and the issuer and client
# credentials are present.
module RizzSignIn
  Error = RizzAuth::Error
  InvalidToken = RizzAuth::InvalidToken
  Unavailable = RizzAuth::Unavailable
  Configuration = RizzAuth::Configuration
  HttpClient = RizzAuth::HttpClient
  JwksClient = RizzAuth::JwksClient
  TokenVerifier = RizzAuth::TokenVerifier
  Client = RizzAuth::Client

  def self.configuration
    RizzAuth.configuration
  end

  def self.enabled?
    RizzAuth.enabled?
  end

  def self.google_proof_enabled?
    Voter.google_sign_in_available?
  end

  # "t•••@example.com": enough for a person to recognise their own address, not enough to disclose it.
  def self.mask_email(email)
    RizzAuth.mask_email(email)
  end
end
