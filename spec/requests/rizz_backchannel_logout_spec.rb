# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rizz back-channel logout", type: :request do
  include_context "with a Rizz speaker"

  let(:voter) { create(:voter) }
  let!(:binding) { VoterRizzBinding.create!(voter: voter, rizz_sub: "pairwise-sub-1", operation_id: "op-1", rizz_session_epoch: 2, connected_at: Time.current) }

  def logout(token)
    post "/auth/rizz/backchannel_logout", params: { logout_token: token }
  end

  def sign_in_with_rizz
    speaker.issue_id_tokens_with(epoch: binding.reload.rizz_session_epoch)
    post rizz_auth_path
    get speaker.authorize(response.location)
    expect(request.env["warden"].user(:voter)).to eq(voter)
  end

  it "adopts the Speaker's exact epoch (no local +1), marks the binding disconnected, and returns 200" do
    logout speaker.logout_token(epoch: 3)
    expect(response).to have_http_status(:ok)
    expect(binding.reload).to have_attributes(status: "disconnected", rizz_session_epoch: 3)
    expect(binding.disconnected_at).to be_present
    expect(RizzBackchannelLogoutEvent.last).to have_attributes(rizz_sub: "pairwise-sub-1", rizz_epoch: 3)
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "ignores a stale logout (epoch not ahead of the binding), recording its jti but changing nothing" do
    [ 1, 2 ].each do |epoch|
      logout speaker.logout_token(epoch: epoch)
      expect(response).to have_http_status(:ok)
      expect(binding.reload).to have_attributes(status: "active", rizz_session_epoch: 2, disconnected_at: nil)
    end
    expect(RizzBackchannelLogoutEvent.count).to eq(2)
  end

  it "does not disconnect a re-claimed binding when the logout that preceded the re-claim is redelivered late" do
    logout speaker.logout_token(epoch: 3)
    expect(binding.reload.status).to eq("disconnected")

    receipt = RizzClaimReceipt.issue!(voter: voter, operation_id: "op-2")
    post "/auth/rizz/claim/exchange",
      params: { operation_id: "op-2", receipt: receipt, rizz_sub: "pairwise-sub-1", rizz_session_epoch: 3 }.to_json,
      headers: rizz_basic_auth.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(binding.reload).to have_attributes(status: "active", rizz_session_epoch: 3)

    logout speaker.logout_token(epoch: 3)
    expect(response).to have_http_status(:ok)
    expect(binding.reload).to have_attributes(status: "active", rizz_session_epoch: 3, disconnected_at: nil)

    logout speaker.logout_token(epoch: 4)
    expect(binding.reload).to have_attributes(status: "disconnected", rizz_session_epoch: 4)
  end

  it "jumps to the token's epoch when that is ahead" do
    logout speaker.logout_token(epoch: 7)
    expect(binding.reload.rizz_session_epoch).to eq(7)
  end

  it "applies a redelivered jti only once" do
    token = speaker.logout_token(epoch: 3, jti: "same-jti")
    logout token
    binding.reload.update!(status: "active", disconnected_at: nil)
    logout token
    expect(response).to have_http_status(:ok)
    expect(binding.reload).to have_attributes(status: "active", rizz_session_epoch: 3)
    expect(RizzBackchannelLogoutEvent.count).to eq(1)
  end

  it "acknowledges a subject with no binding" do
    logout speaker.logout_token(sub: "unknown-sub")
    expect(response).to have_http_status(:ok)
    expect(binding.reload).to have_attributes(status: "active", rizz_session_epoch: 2)
  end

  {
    "a bad signature" => { signing_key: OpenSSL::PKey::EC.generate("prime256v1") },
    "an expired token" => { iat: 2.hours.ago.to_i, exp: 1.hour.ago.to_i },
    "another audience" => { aud: "other-client" },
    "another issuer" => { iss: "https://evil.example" },
    "the wrong typ" => { typ: "JWT" },
    "no logout event" => { events: {} },
    "a nonce claim" => { nonce: "forbidden" },
    "no jti" => { jti: nil },
    "no epoch" => { rizz_epoch: nil }
  }.each do |description, overrides|
    it "rejects #{description} with 400 and changes nothing" do
      overrides = overrides.dup
      typ = overrides.delete(:typ)
      logout speaker.logout_token(**{ typ: typ }.compact, **overrides)
      expect(response).to have_http_status(:bad_request)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(binding.reload).to have_attributes(status: "active", rizz_session_epoch: 2)
      expect(RizzBackchannelLogoutEvent.count).to eq(0)
    end
  end

  it "rejects a missing token and an ID token used as a logout token" do
    post "/auth/rizz/backchannel_logout"
    expect(response).to have_http_status(:bad_request)
    logout speaker.id_token(nonce: "n")
    expect(response).to have_http_status(:bad_request)
  end

  it "answers 503 with no-store when the issuer cannot be reached" do
    allow(RizzSignIn::HttpClient).to receive(:get_json).and_raise(RizzSignIn::Unavailable)
    RizzSignIn::JwksClient.reset!
    logout speaker.logout_token(epoch: 3)
    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(binding.reload.status).to eq("active")
  end

  it "keeps accepting logouts, and ends Rizz-opened sessions, after RIZZ_SIGN_IN_ENABLED is turned off" do
    sign_in_with_rizz
    get edit_voter_registration_path
    expect(response).to have_http_status(:ok)

    with_rizz_env("RIZZ_SIGN_IN_ENABLED" => nil) do
      expect(RizzSignIn.enabled?).to be(false)
      expect(RizzSignIn.configuration.configured?).to be(true)
      logout speaker.logout_token(epoch: 3)
      expect(response).to have_http_status(:ok)
      expect(binding.reload).to have_attributes(status: "disconnected", rizz_session_epoch: 3)
    end
  end

  it "signs a still-active Rizz-opened session out on its next request once the feature is turned off" do
    sign_in_with_rizz
    get edit_voter_registration_path
    expect(response).to have_http_status(:ok)

    with_rizz_env("RIZZ_SIGN_IN_ENABLED" => nil) do
      get edit_voter_registration_path
      expect(response).to redirect_to(new_voter_session_path)
      expect(request.env["warden"].user(:voter)).to be_nil
      expect(request.session["rizz_binding_id"]).to be_nil
    end
  end

  it "leaves a password session alone while the feature is off" do
    post voter_session_path, params: { voter: { email: voter.email, password: "password123" } }
    with_rizz_env("RIZZ_SIGN_IN_ENABLED" => nil) do
      get edit_voter_registration_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "needs no session, cookie, or CSRF token" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    logout speaker.logout_token(epoch: 3)
    expect(response).to have_http_status(:ok)
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it "signs a Rizz-opened session out on its next request" do
    sign_in_with_rizz
    get edit_voter_registration_path
    expect(response).to have_http_status(:ok)

    logout speaker.logout_token(epoch: 3)
    expect(response).to have_http_status(:ok)

    get edit_voter_registration_path
    expect(response).to redirect_to(new_voter_session_path)
    expect(request.env["warden"].user(:voter)).to be_nil
    expect(request.session["rizz_binding_id"]).to be_nil
  end

  it "clears remember_voter_token on epoch revocation so remember-me cannot revive the session" do
    post voter_session_path, params: { voter: { email: voter.email, password: "password123", remember_me: "1" } }
    remember_token = cookies[:remember_voter_token]
    expect(remember_token).to be_present

    sign_in_with_rizz
    cookies[:remember_voter_token] = remember_token

    logout speaker.logout_token(epoch: 3)
    expect(response).to have_http_status(:ok)

    get edit_voter_registration_path
    expect(response).to redirect_to(new_voter_session_path)
    expect(Array(response.headers["set-cookie"]).join("\n")).to match(/remember_voter_token=;|remember_voter_token=$/m)
    expect(cookies[:remember_voter_token]).to be_blank

    get edit_voter_registration_path
    expect(response).to redirect_to(new_voter_session_path)
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "signs out when only the epoch is behind, even if the binding was reactivated" do
    sign_in_with_rizz
    binding.update!(rizz_session_epoch: 5)
    get edit_voter_registration_path
    expect(response).to redirect_to(new_voter_session_path)
  end

  it "signs out when the binding is disconnected or belongs to another Voter" do
    sign_in_with_rizz
    binding.update!(status: "disconnected")
    get edit_voter_registration_path
    expect(response).to redirect_to(new_voter_session_path)

    binding.update!(status: "active")
    sign_in_with_rizz
    binding.update_columns(voter_id: create(:voter).id)
    get edit_voter_registration_path
    expect(response).to redirect_to(new_voter_session_path)
  end

  it "does not touch a password session for the same Voter" do
    post voter_session_path, params: { voter: { email: voter.email, password: "password123" } }
    get edit_voter_registration_path
    expect(response).to have_http_status(:ok)
    logout speaker.logout_token(epoch: 3)
    get edit_voter_registration_path
    expect(response).to have_http_status(:ok)
    expect(request.env["warden"].user(:voter)).to eq(voter)
  end

  it "does not touch a Google-opened session for the same Voter" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "g-1",
      info: { email: voter.email, first_name: voter.first_name, last_name: voter.last_name, email_verified: true }
    )
    post voter_google_oauth2_omniauth_authorize_path
    follow_redirect!
    expect(request.env["warden"].user(:voter)).to eq(voter)
    logout speaker.logout_token(epoch: 3)
    get edit_voter_registration_path
    expect(response).to have_http_status(:ok)
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  it "lets the Voter sign in with Rizz again after a fresh claim at the new epoch" do
    logout speaker.logout_token(epoch: 3)
    speaker.issue_id_tokens_with(epoch: 3)
    post rizz_auth_path
    get speaker.authorize(response.location)
    expect(request.env["warden"].user(:voter)).to be_nil
    binding.reload.update!(status: "active", disconnected_at: nil)
    post rizz_auth_path
    get speaker.authorize(response.location)
    expect(request.env["warden"].user(:voter)).to eq(voter)
  end
end
