# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sign in with Rizz", type: :request do
  include_context "with a Rizz speaker"

  let(:voter) { create(:voter) }
  let!(:binding) { VoterRizzBinding.create!(voter: voter, rizz_sub: "pairwise-sub-1", operation_id: "op-1", rizz_session_epoch: 2, connected_at: Time.current) }

  before { speaker.issue_id_tokens_with(epoch: 2) }

  # Drives POST /auth/rizz, the Speaker's authorize step, and the callback; returns the callback response.
  def sign_in_with_rizz(code_tamper: nil)
    post rizz_auth_path
    expect(response).to have_http_status(:see_other)
    callback_url = speaker.authorize(response.location)
    callback_url = code_tamper.call(callback_url) if code_tamper
    get callback_url
  end

  it "is hidden and returns 404 until it is enabled" do
    with_rizz_env("RIZZ_SIGN_IN_ENABLED" => nil) do
      get new_voter_session_path
      expect(response.body).not_to include("Sign in with Rizz")
      post rizz_auth_path
      expect(response).to have_http_status(:not_found)
      get rizz_auth_callback_path
      expect(response).to have_http_status(:not_found)
    end
    with_rizz_env("RIZZ_OIDC_CLIENT_SECRET" => nil) { expect(RizzSignIn.enabled?).to be(false) }
  end

  it "shows a POST button next to Google and password with a single divider" do
    get new_voter_session_path
    page = Nokogiri::HTML(response.body)
    form = page.at_css("form[action='/auth/rizz']")
    expect(form["method"]).to eq("post")
    expect(form["data-turbo"]).to eq("false")
    expect(form.text).to include("Sign in with Rizz")
    expect(page.css(".auth-divider").size).to eq(1)
    expect(response.body).to include("Continue with Google", "voter_password")

    allow(Voter).to receive(:google_sign_in_available?).and_return(false)
    get new_voter_session_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".auth-google")).to be_nil
    expect(page.at_css("form[action='/auth/rizz']")).to be_present
    expect(page.css(".auth-divider").size).to eq(1)
  end

  it "starts an S256 PKCE authorization code request with an encrypted HttpOnly flow cookie and frame-ancestors none" do
    post rizz_auth_path
    uri = URI(response.location)
    query = Rack::Utils.parse_query(uri.query)
    expect(uri.to_s).to start_with("https://rizz.test/oauth/authorize?")
    expect(query).to include(
      "client_id" => RizzSpeaker::CLIENT_ID,
      "response_type" => "code",
      "scope" => "openid",
      "code_challenge_method" => "S256",
      "redirect_uri" => rizz_auth_callback_url
    )
    expect(query.values_at("state", "nonce", "code_challenge")).to all(be_present)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Content-Security-Policy"]).to include("frame-ancestors 'none'")
    cookie = Array(response.headers["set-cookie"]).find { it.start_with?("rizz_auth_flow=") }
    expect(cookie).to match(/rizz_auth_flow=/i)
    expect(cookie).to match(/httponly/i)
    expect(cookie).not_to include(query["state"])
  end

  it "signs the bound Voter in without remember-me and marks the session as opened by Rizz" do
    sign_in_with_rizz
    expect(response).to redirect_to(root_path)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Content-Security-Policy"]).to include("frame-ancestors 'none'")
    expect(request.env["warden"].user(:voter)).to eq(voter)
    expect(request.session["rizz_binding_id"]).to eq(binding.id)
    expect(request.session["rizz_session_epoch"]).to eq(2)
    expect(response.headers["set-cookie"].to_s).not_to include("remember_voter_token")
    expect(voter.reload.remember_created_at).to be_nil
    get edit_voter_registration_path
    expect(response).to have_http_status(:ok)
  end

  it "clears any existing remember_voter_token cookie on Rizz sign-in" do
    post voter_session_path, params: { voter: { email: voter.email, password: "password123", remember_me: "1" } }
    expect(cookies[:remember_voter_token]).to be_present

    sign_in_with_rizz
    expect(response).to redirect_to(root_path)
    expect(Array(response.headers["set-cookie"]).join("\n")).to match(/remember_voter_token=;|remember_voter_token=$/m)
    expect(cookies[:remember_voter_token]).to be_blank
  end

  it "does not sign in again with a replayed authorization code" do
    sign_in_with_rizz
    callback_url = speaker.codes.values.first[:query]["redirect_uri"]
    delete destroy_voter_session_path
    post rizz_auth_path
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]
    get "#{callback_url}?#{{ code: "already-used-code", state: state }.to_query}"
    expect(response).to redirect_to(new_voter_session_path)
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "rejects a code the Speaker already consumed" do
    sign_in_with_rizz
    used = speaker.codes.values.first
    expect(used[:consumed]).to be(true)
    expect { speaker.post_form("#{RizzSpeaker::ISSUER}/oauth/token", { code: "x" }, basic_auth: %w[a b]) }.to raise_error(RizzSignIn::Unavailable)
  end

  it "rejects a missing flow cookie or a wrong state" do
    post rizz_auth_path
    callback_url = speaker.authorize(response.location)
    reset!
    get callback_url
    expect(response).to redirect_to(new_voter_session_path)
    expect(request.env["warden"].user(:voter)).to be_nil

    post rizz_auth_path
    callback_url = speaker.authorize(response.location)
    get callback_url.sub(/state=[^&]+/, "state=forged")
    expect(response).to redirect_to(new_voter_session_path)
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "does not let the flow cookie be used twice" do
    post rizz_auth_path
    callback_url = speaker.authorize(response.location)
    get callback_url
    expect(request.env["warden"].user(:voter)).to eq(voter)
    delete destroy_voter_session_path
    get callback_url
    expect(response).to redirect_to(new_voter_session_path)
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  {
    "an expired ID token" => { iat: 2.hours.ago.to_i, exp: 1.hour.ago.to_i },
    "an ID token for another audience" => { aud: "someone-else" },
    "an ID token from another issuer" => { iss: "https://evil.example" },
    "an ID token with the wrong nonce" => { nonce_override: "not-the-nonce" },
    "an ID token with the wrong typ" => { typ: "at+jwt" },
    "an ID token missing its epoch" => { rizz_epoch: nil },
    "an ID token signed by an unknown key" => { signing_key: OpenSSL::PKey::EC.generate("prime256v1") },
    "an ID token naming an unknown kid" => { key_id: "not-in-jwks" }
  }.each do |description, overrides|
    it "rejects #{description}" do
      overrides = overrides.dup
      speaker.define_singleton_method(:post_form) do |url, params, basic_auth:|
        super(url, params, basic_auth: basic_auth).merge(
          "id_token" => id_token(nonce: overrides.delete(:nonce_override) || codes.values.last[:query]["nonce"], **overrides)
        )
      end
      sign_in_with_rizz
      expect(response).to redirect_to(new_voter_session_path)
      expect(request.env["warden"].user(:voter)).to be_nil
    end
  end

  it "rejects an ID token that is not ES256" do
    speaker.define_singleton_method(:post_form) do |url, params, basic_auth:|
      nonce = codes.values.last[:query]["nonce"]
      super(url, params, basic_auth: basic_auth).merge(
        "id_token" => JWT.encode(base_claims("sub" => "pairwise-sub-1", "nonce" => nonce, "rizz_epoch" => 2), "a-shared-secret", "HS256", { typ: "JWT", kid: kid })
      )
    end
    sign_in_with_rizz
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "rejects an unsigned (alg none) ID token" do
    speaker.define_singleton_method(:post_form) do |url, params, basic_auth:|
      nonce = codes.values.last[:query]["nonce"]
      super(url, params, basic_auth: basic_auth).merge(
        "id_token" => JWT.encode(base_claims("sub" => "pairwise-sub-1", "nonce" => nonce, "rizz_epoch" => 2), nil, "none", { typ: "JWT", kid: kid })
      )
    end
    sign_in_with_rizz
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "rejects an ID token whose epoch is behind the binding" do
    speaker.issue_id_tokens_with(epoch: 1)
    sign_in_with_rizz
    expect(response).to redirect_to(new_voter_session_path)
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "atomically adopts a newer epoch, invalidating older sessions and ignoring delayed logouts for earlier epochs" do
    older_browser = open_session
    older_browser.post rizz_auth_path
    older_browser.get speaker.authorize(older_browser.response.location)
    older_browser.get edit_voter_registration_path
    expect(older_browser.response).to have_http_status(:ok)

    speaker.issue_id_tokens_with(epoch: 5)
    sign_in_with_rizz
    expect(request.env["warden"].user(:voter)).to eq(voter)
    expect(binding.reload.rizz_session_epoch).to eq(5)
    expect(request.session["rizz_session_epoch"]).to eq(5)

    older_browser.get edit_voter_registration_path
    expect(older_browser.response).to have_http_status(:found)
    expect(URI(older_browser.response.location).path).to eq(new_voter_session_path)
    expect(older_browser.request.env["warden"].user(:voter)).to be_nil

    post "/auth/rizz/backchannel_logout", params: { logout_token: speaker.logout_token(epoch: 4) }
    expect(response).to have_http_status(:ok)
    expect(binding.reload).to have_attributes(status: "active", rizz_session_epoch: 5)

    get edit_voter_registration_path
    expect(response).to have_http_status(:ok)
  end

  it "explains when the Rizz account has no active binding" do
    speaker.issue_id_tokens_with(sub: "someone-unbound")
    sign_in_with_rizz
    expect(response).to redirect_to(new_voter_session_path)
    follow_redirect!
    expect(response.body).to include("isn&#39;t connected to an Ascent account yet")
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "ignores a disconnected binding" do
    binding.update!(status: "disconnected", disconnected_at: Time.current)
    sign_in_with_rizz
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "does not sign in an unconfirmed Voter" do
    voter.update!(confirmed_at: nil)
    sign_in_with_rizz
    expect(response).to redirect_to(new_voter_session_path)
    expect(request.env["warden"].user(:voter)).to be_nil
  end

  it "reports an unavailable issuer without signing in" do
    allow(RizzSignIn::HttpClient).to receive(:get_json).and_raise(RizzSignIn::Unavailable)
    RizzSignIn::JwksClient.reset!
    post rizz_auth_path
    expect(response).to redirect_to(new_voter_session_path)
  end

  it "requires a Rails CSRF token to start" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post rizz_auth_path
    expect(response.location.to_s).not_to start_with(RizzSpeaker::ISSUER)
    expect(speaker.fetches).to be_empty
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  context "with a stale Rizz marker left in the session" do
    let(:old_voter) { create(:voter) }
    let!(:old_binding) { VoterRizzBinding.create!(voter: old_voter, rizz_sub: "old-sub", operation_id: "old-op", rizz_session_epoch: 1, connected_at: Time.current) }

    def leave_stale_marker
      speaker.issue_id_tokens_with(sub: "old-sub", epoch: 1)
      sign_in_with_rizz
      expect(request.session["rizz_binding_id"]).to eq(old_binding.id)
      Warden.on_next_request { |proxy| proxy.logout(:voter) }
      get new_voter_session_path
      expect(request.env["warden"].user(:voter)).to be_nil
      expect(request.session["rizz_binding_id"]).to eq(old_binding.id)
      old_binding.update!(status: "disconnected", disconnected_at: Time.current)
    end

    it "leaves password sign-in unaffected" do
      other = create(:voter, email: "direct@example.com", password: "password123")
      leave_stale_marker
      post voter_session_path, params: { voter: { email: other.email, password: "password123" } }
      get edit_voter_registration_path
      expect(response).to have_http_status(:ok)
      expect(request.env["warden"].user(:voter)).to eq(other)
      expect(request.session["rizz_binding_id"]).to be_nil
      expect(request.session["rizz_session_epoch"]).to be_nil
    end

    it "leaves a fresh Sign in with Rizz unaffected and replaces the marker" do
      leave_stale_marker
      speaker.issue_id_tokens_with(epoch: 2)
      sign_in_with_rizz
      expect(response).to redirect_to(root_path)
      get edit_voter_registration_path
      expect(response).to have_http_status(:ok)
      expect(request.env["warden"].user(:voter)).to eq(voter)
      expect(request.session["rizz_binding_id"]).to eq(binding.id)
      expect(request.session["rizz_session_epoch"]).to eq(2)
    end

    it "clears the marker on any non-fetch sign-in event, such as a bare Devise sign_in" do
      leave_stale_marker
      sign_in voter
      get edit_voter_registration_path
      expect(response).to have_http_status(:ok)
      expect(request.env["warden"].user(:voter)).to eq(voter)
      expect(request.session["rizz_binding_id"]).to be_nil
    end
  end

  it "rotates the CSRF token when signing in with Rizz" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get new_voter_session_path
    before_token = request.session["_csrf_token"]
    expect(before_token).to be_present
    token = Nokogiri::HTML(response.body).at_css("form[action='/auth/rizz'] input[name=authenticity_token]")["value"]
    post rizz_auth_path, params: { authenticity_token: token }
    expect(response.location).to start_with(RizzSpeaker::ISSUER)
    callback_url = speaker.authorize(response.location)
    get callback_url
    expect(request.env["warden"].user(:voter)).to eq(voter)
    expect(request.session["_csrf_token"]).not_to eq(before_token)
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it "stays hidden and 404s on the sign-in endpoints while configured but switched off" do
    with_rizz_env("RIZZ_SIGN_IN_ENABLED" => "0") do
      expect(RizzSignIn.configuration).to be_configured
      expect(RizzSignIn).not_to be_enabled
      post rizz_auth_path
      expect(response).to have_http_status(:not_found)
    end
  end
end
