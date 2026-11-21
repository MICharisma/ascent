# frozen_string_literal: true

# An in-process stand-in for the Rizz Speaker: signs ES256 tokens, serves discovery/JWKS, and runs the
# authorize and token legs (with real S256 PKCE and single-use codes) through RizzSignIn::HttpClient.
class RizzSpeaker
  ISSUER = "https://rizz.test"
  CLIENT_ID = "ascent-client"
  CLIENT_SECRET = "ascent-secret"

  attr_reader :key, :kid, :codes, :fetches

  def initialize(kid: "speaker-1")
    @key = OpenSSL::PKey::EC.generate("prime256v1")
    @kid = kid
    @codes = {}
    @fetches = []
    @extra_keys = []
  end

  def jwks
    { "keys" => ([ [ key, kid ] ] + @extra_keys).map { |signing_key, key_id| jwk(signing_key, key_id) } }
  end

  def rotate!(new_kid: "speaker-2")
    @extra_keys << [ key, kid ]
    @key = OpenSSL::PKey::EC.generate("prime256v1")
    @kid = new_kid
  end

  def discovery
    {
      "issuer" => ISSUER,
      "authorization_endpoint" => "#{ISSUER}/oauth/authorize",
      "token_endpoint" => "#{ISSUER}/oauth/token",
      "jwks_uri" => "#{ISSUER}/.well-known/jwks.json",
      "response_types_supported" => [ "code" ],
      "subject_types_supported" => [ "pairwise" ],
      "id_token_signing_alg_values_supported" => [ "ES256" ],
      "code_challenge_methods_supported" => [ "S256" ],
      "backchannel_logout_supported" => true,
      "backchannel_logout_session_supported" => false
    }
  end

  def sign(payload, typ:, signing_key: key, key_id: kid, alg: "ES256")
    JWT.encode(payload, signing_key, alg, { typ: typ, kid: key_id }.compact)
  end

  def base_claims(overrides = {})
    now = Time.now.to_i
    { "iss" => ISSUER, "aud" => CLIENT_ID, "iat" => now, "exp" => now + 300 }.merge(overrides.transform_keys(&:to_s)).compact
  end

  def id_token(sub: "pairwise-sub-1", nonce:, epoch: 1, typ: "JWT", **overrides)
    sign(base_claims({ "sub" => sub, "nonce" => nonce, "rizz_epoch" => epoch }.merge(overrides)), typ: typ, **signing_options(overrides))
  end

  def claim_handoff(operation_id: "op-1", speaker_label: "Marcus T. (Rizz)", callback_uri: "#{ISSUER}/claims/op-1/return", jti: SecureRandom.uuid, **overrides)
    sign(
      base_claims({ "jti" => jti, "operation_id" => operation_id, "speaker_label" => speaker_label, "callback_uri" => callback_uri }.merge(overrides)),
      typ: "rizz-claim-handoff+jwt",
      **signing_options(overrides)
    )
  end

  def create_handoff(operation_id: "op-1", speaker_label: "Marcus T. (Rizz)", callback_uri: "#{ISSUER}/claims/op-1/return", jti: SecureRandom.uuid,
    email: "marcus.tate@gmail.com", display_name: "Marcus Tate", **overrides)
    sign(
      base_claims({ "jti" => jti, "operation_id" => operation_id, "speaker_label" => speaker_label, "callback_uri" => callback_uri,
        "email" => email, "display_name" => display_name }.merge(overrides)),
      typ: "rizz-create-handoff+jwt",
      **signing_options(overrides)
    )
  end

  def logout_token(sub: "pairwise-sub-1", epoch: 2, jti: SecureRandom.uuid, typ: "logout+jwt", **overrides)
    events = { "http://schemas.openid.net/event/backchannel-logout" => {} }
    sign(base_claims({ "sub" => sub, "jti" => jti, "events" => events, "rizz_epoch" => epoch }.merge(overrides)), typ: typ, **signing_options(overrides))
  end

  # What the Speaker's /oauth/authorize does for a signed-in speaker: validate, mint a code, return the callback URL.
  def authorize(authorization_url)
    uri = URI(authorization_url)
    query = Rack::Utils.parse_query(uri.query)
    unless uri.to_s.start_with?("#{ISSUER}/oauth/authorize") &&
        query.values_at("client_id", "response_type", "scope", "code_challenge_method") == [ CLIENT_ID, "code", "openid", "S256" ] &&
        query.values_at("state", "nonce", "code_challenge", "redirect_uri").all?(&:present?)
      raise "unexpected authorize request: #{query}"
    end

    code = SecureRandom.urlsafe_base64(24)
    codes[Digest::SHA256.hexdigest(code)] = { query: query, issued_at: Time.now, consumed: false }
    "#{query["redirect_uri"]}?#{{ code: code, state: query["state"] }.to_query}"
  end

  def get_json(url)
    fetches << url
    case url
    when "#{ISSUER}/.well-known/openid-configuration" then discovery
    when "#{ISSUER}/.well-known/jwks.json" then jwks
    else raise RizzSignIn::Unavailable, "no such url #{url}"
    end
  end

  def post_form(url, params, basic_auth:)
    raise RizzSignIn::Unavailable, "401" unless url == "#{ISSUER}/oauth/token" && basic_auth == [ CLIENT_ID, CLIENT_SECRET ]

    entry = codes[Digest::SHA256.hexdigest(params[:code].to_s)]
    raise RizzSignIn::Unavailable, "invalid_grant" if entry.nil? || entry[:consumed] || entry[:issued_at] < 60.seconds.ago

    entry[:consumed] = true
    query = entry[:query]
    pkce_ok = Base64.urlsafe_encode64(Digest::SHA256.digest(params[:code_verifier].to_s), padding: false) == query["code_challenge"]
    raise RizzSignIn::Unavailable, "invalid_grant" unless pkce_ok && params[:redirect_uri] == query["redirect_uri"] && params[:grant_type] == "authorization_code"

    { "token_type" => "Bearer", "expires_in" => 300, "id_token" => id_token(nonce: query["nonce"], **(@id_token_options || {})) }
  end

  # Options merged into the ID tokens the token endpoint issues, e.g. epoch: 3 or typ: "at+jwt".
  def issue_id_tokens_with(**options)
    @id_token_options = options
  end

  private

  def jwk(signing_key, key_id)
    JWT::JWK.new(signing_key, { kid: key_id, alg: "ES256", use: "sig" }).export.transform_keys(&:to_s)
  end

  def signing_options(overrides)
    options = {}
    options[:signing_key] = overrides[:signing_key] if overrides.key?(:signing_key)
    options[:key_id] = overrides[:key_id] if overrides.key?(:key_id)
    options
  end
end

module RizzSpecHelpers
  RIZZ_ENV = {
    "RIZZ_SIGN_IN_ENABLED" => "1",
    "RIZZ_OIDC_ISSUER" => RizzSpeaker::ISSUER,
    "RIZZ_OIDC_CLIENT_ID" => RizzSpeaker::CLIENT_ID,
    "RIZZ_OIDC_CLIENT_SECRET" => RizzSpeaker::CLIENT_SECRET
  }.freeze

  def with_rizz_env(overrides = {})
    env = RIZZ_ENV.merge(overrides.transform_keys(&:to_s))
    saved = (RIZZ_ENV.keys | env.keys).to_h { [ it, ENV[it] ] }
    saved.each_key { |name| env[name].nil? ? ENV.delete(name) : ENV[name] = env[name] }
    yield
  ensure
    saved.each { |name, value| value ? ENV[name] = value : ENV.delete(name) }
  end

  def install_rizz_speaker(speaker)
    RizzSignIn::JwksClient.reset!
    allow(RizzSignIn::HttpClient).to receive(:get_json) { |url| speaker.get_json(url) }
    allow(RizzSignIn::HttpClient).to receive(:post_form) { |url, params, basic_auth:| speaker.post_form(url, params, basic_auth: basic_auth) }
  end

  def rizz_basic_auth(id: RizzSpeaker::CLIENT_ID, secret: RizzSpeaker::CLIENT_SECRET)
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(id, secret) }
  end
end

RSpec.configure do |config|
  config.include RizzSpecHelpers
  config.after { RizzSignIn::JwksClient.reset! }
end

RSpec.shared_context "with a Rizz speaker" do
  let(:speaker) { RizzSpeaker.new }

  around { |example| with_rizz_env { example.run } }
  before { install_rizz_speaker(speaker) }
end
