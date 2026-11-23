# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rizz create", type: :request do
  include_context "with a Rizz speaker"

  let(:callback_uri) { "#{RizzSpeaker::ISSUER}/claims/op-1/return" }
  let(:email) { "marcus.tate@gmail.com" }
  let(:onboarding) do
    {
      voter: {
        first_name: "Marcus",
        last_name: "Tate",
        username: "marcus_tate",
        display_name: "Marcus Tate",
        password: "hardwood-9",
        password_confirmation: "hardwood-9"
      }
    }
  end

  def start_create(**overrides)
    post rizz_create_start_path, params: { handoff: speaker.create_handoff(callback_uri: callback_uri, email: email, **overrides) }
  end

  def submit(attributes = onboarding)
    post rizz_create_path, params: attributes
  end

  def redirect_path(session)
    expect(session.response).to have_http_status(:see_other)
    URI(session.response.location).path
  end

  def set_cookies
    Array(response.headers["set-cookie"]).join("\n")
  end

  def receipt_from_redirect
    Rack::Utils.parse_query(URI(response.location).query).fetch("receipt")
  end

  def exchange(receipt:, operation_id: "op-1", rizz_sub: "pairwise-sub-1", epoch: 3, headers: rizz_basic_auth)
    post "/auth/rizz/claim/exchange",
      params: { operation_id: operation_id, receipt: receipt, rizz_sub: rizz_sub, rizz_session_epoch: epoch }.to_json,
      headers: headers.merge("Content-Type" => "application/json")
  end

  describe "start" do
    it "verifies the handoff, stores the verified email server-side, and sets an encrypted HttpOnly create cookie" do
      expect { start_create(email: "  Marcus.Tate@Gmail.com ") }.not_to change(Voter, :count)
      expect(response).to redirect_to(rizz_create_path)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["Content-Security-Policy"]).to include("frame-ancestors 'none'")
      handoff = RizzClaimHandoff.last
      expect(handoff).to have_attributes(
        intent: "create",
        operation_id: "op-1",
        speaker_label: "Marcus T. (Rizz)",
        callback_uri: callback_uri,
        email: "marcus.tate@gmail.com",
        display_name: "Marcus Tate",
        encrypted_password: nil,
        verified_voter_id: nil,
        consumed_at: nil
      )
      cookie = set_cookies
      expect(cookie).to match(/rizz_create_local=/)
      expect(cookie).to match(/httponly/i)
      expect(cookie).not_to include(handoff.id)
      expect(cookie).not_to match(/rizz_claim_local=/)
    end

    it "uses a __Host- cookie under HTTPS" do
      https!
      start_create
      expect(set_cookies).to match(/__Host-rizz_create_local=.*secure/i)
    end

    it "expires the handoff with the signed exp, never later than the normal claim lifetime" do
      start_create(exp: Time.now.to_i + 120)
      expect(RizzClaimHandoff.last.expires_at).to be_within(5.seconds).of(2.minutes.from_now)
      reset!
      start_create(jti: "full", exp: Time.now.to_i + 300)
      expect(RizzClaimHandoff.last.expires_at).to be_within(5.seconds).of(5.minutes.from_now)
    end

    it "refuses onboarding once the signed exp has passed" do
      start_create(exp: Time.now.to_i + 120)
      RizzClaimHandoff.last.update!(expires_at: 1.second.ago)
      submit
      expect(response).to redirect_to(new_voter_session_path)
      expect(RizzClaimReceipt.count).to eq(0)
    end

    it "is POST-only" do
      get "/auth/rizz/create/start", params: { handoff: speaker.create_handoff(callback_uri: callback_uri) }
      expect(response).to have_http_status(:not_found)
      expect(RizzClaimHandoff.count).to eq(0)
    end

    it "accepts the cross-site POST without a CSRF token, while onboarding and cancel still require one" do
      ActionController::Base.allow_forgery_protection = true
      start_create
      expect(response).to redirect_to(rizz_create_path)
      submit
      expect(response).to have_http_status(:unprocessable_content)
      post rizz_create_cancel_path
      expect(response).to have_http_status(:unprocessable_content)
      expect(RizzClaimHandoff.last.consumed_at).to be_nil
      expect(RizzClaimReceipt.count).to eq(0)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "refuses a replayed handoff jti, even after it was spent" do
      jwt = speaker.create_handoff(callback_uri: callback_uri, jti: "one-use", email: email)
      post rizz_create_start_path, params: { handoff: jwt }
      submit
      reset!
      post rizz_create_start_path, params: { handoff: jwt }
      expect(response).to redirect_to(new_voter_session_path)
      expect(RizzClaimHandoff.count).to eq(1)
    end

    {
      "a bad signature" => { signing_key: OpenSSL::PKey::EC.generate("prime256v1") },
      "an expired handoff" => { iat: 2.hours.ago.to_i, exp: 1.hour.ago.to_i },
      "a lifetime over five minutes" => { iat: Time.now.to_i - 5, exp: Time.now.to_i + 296 + 10 },
      "another audience" => { aud: "other-client" },
      "another issuer" => { iss: "https://evil.example" },
      "a callback on another origin" => { callback_uri: "https://evil.example/claims/op-1/return" },
      "a plain http callback" => { callback_uri: "http://rizz.test/claims/op-1/return" },
      "a callback with credentials" => { callback_uri: "https://user:pass@rizz.test/claims/op-1/return" },
      "an overlong speaker label" => { speaker_label: "M" * 121 },
      "no email" => { email: "" },
      "a non-string email" => { email: [ "marcus.tate@gmail.com" ] },
      "a malformed email" => { email: "not-an-email" },
      "a non-string display name" => { display_name: 42 },
      "an overlong display name" => { display_name: "M" * 61 }
    }.each do |description, overrides|
      it "rejects #{description}" do
        start_create(**overrides)
        expect(response).to redirect_to(new_voter_session_path)
        expect(RizzClaimHandoff.count).to eq(0)
      end
    end

    it "rejects a claim handoff, an ID token, and a missing or non-string handoff" do
      [ speaker.claim_handoff(callback_uri: callback_uri), speaker.id_token(nonce: "n") ].each do |token|
        post rizz_create_start_path, params: { handoff: token }
        expect(response).to redirect_to(new_voter_session_path)
      end
      post rizz_create_start_path
      expect(response).to redirect_to(new_voter_session_path)
      post rizz_create_start_path, params: { handoff: { jti: "x" } }
      expect(response).to redirect_to(new_voter_session_path)
      expect(RizzClaimHandoff.count).to eq(0)
    end

    it "does not let the claim start accept a create handoff" do
      post rizz_claim_start_path, params: { handoff: speaker.create_handoff(callback_uri: callback_uri) }
      expect(response).to redirect_to(new_voter_session_path)
      expect(RizzClaimHandoff.count).to eq(0)
    end

    it "does not log the raw handoff or password" do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      original = Rails.logger
      Rails.logger = logger
      ActionController::Base.logger = logger
      jwt = speaker.create_handoff(callback_uri: callback_uri)
      post rizz_create_start_path, params: { handoff: jwt }
      submit
      expect(io.string).not_to include(jwt, "hardwood-9", email)
    ensure
      Rails.logger = original
      ActionController::Base.logger = original
    end
  end

  describe "onboarding form" do
    before { start_create }

    it "shows readonly verified email, prefills first/last name from display_name, and renders a collapsed optional password over a no-Turbo form" do
      get rizz_create_path
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["Content-Security-Policy"]).to include("frame-ancestors 'none'")
      page = Nokogiri::HTML(response.body)
      form = page.at_css("form[action='#{rizz_create_path}']")
      expect(form["data-turbo"]).to eq("false")
      expect(form.at_css("input[type=email][readonly]")["value"]).to eq(email)
      expect(form.at_css("input[name='voter[first_name]']")["value"]).to eq("Marcus")
      expect(form.at_css("input[name='voter[last_name]']")["value"]).to eq("Tate")
      expect(form.at_css("input[name='voter[username]']")["readonly"]).to be_nil
      expect(form.at_css("input[name='voter[display_name]']")["value"]).to eq("Marcus Tate")
      details = form.at_css("details")
      expect(details.at_css("summary").text).to eq("Set a password (optional)")
      expect(details["open"]).to be_nil
      %w[password password_confirmation].each do |field|
        input = details.at_css("input[name='voter[#{field}]'][type=password]")
        expect(input).to be_present
        expect(input["required"]).to be_nil
      end
      expect(form.at_css("input[type=submit]")["value"]).to eq("Create account")
      expect(page.at_css("form[action='#{rizz_create_cancel_path}']").text).to include("Cancel")
    end

    it "prefills single-word and multi-word display names cleanly" do
      reset!
      start_create(jti: "single-name", display_name: "Madonna")
      get rizz_create_path
      form = Nokogiri::HTML(response.body).at_css("form[action='#{rizz_create_path}']")
      expect(form.at_css("input[name='voter[first_name]']")["value"]).to eq("Madonna")
      expect(form.at_css("input[name='voter[last_name]']")["value"]).to be_nil

      reset!
      start_create(jti: "multi-name", display_name: "Mary Jane Watson")
      get rizz_create_path
      form = Nokogiri::HTML(response.body).at_css("form[action='#{rizz_create_path}']")
      expect(form.at_css("input[name='voter[first_name]']")["value"]).to eq("Mary")
      expect(form.at_css("input[name='voter[last_name]']")["value"]).to eq("Jane Watson")
    end

    it "ignores a posted email" do
      submit voter: onboarding[:voter].merge(email: "someone.else@example.com")
      expect(RizzClaimHandoff.last.email).to eq(email)
      expect(RizzClaimReceipt.last.handoff).to eq(RizzClaimHandoff.last)
    end

    it "omits the signed-in browser notice when signed out" do
      get rizz_create_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("This browser is currently signed in as")
    end

    it "shows the signed-in browser notice on initial GET and invalid POST re-render when signed in" do
      signed_in = create(:voter, username: "ballot_tess")
      sign_in signed_in

      get rizz_create_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This browser is currently signed in as @ballot_tess. Creating a new account here won&#39;t change that session.")

      submit voter: onboarding[:voter].merge(username: "ab")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("This browser is currently signed in as @ballot_tess. Creating a new account here won&#39;t change that session.")
    end
  end

  describe "happy path" do
    # Submits the form and returns the receipt Rizz is redirected back with.
    def submit_for_receipt
      start_create
      get rizz_create_path
      submit
      Rack::Utils.parse_query(URI(response.location).query).fetch("receipt")
    end

    def spend(receipt)
      reset!
      exchange(receipt: receipt)
    end

    it "stores a receipt and the held details, and builds no Voter until the Speaker spends it" do
      start_create
      get rizz_create_path
      expect { submit }.not_to change(Voter, :count)
      expect(response).to have_http_status(:see_other)
      uri = URI(response.location)
      query = Rack::Utils.parse_query(uri.query)
      expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq(callback_uri)
      expect(query["operation_id"]).to eq("op-1")
      stored = RizzClaimReceipt.last
      expect(stored).to have_attributes(voter_id: nil, handoff: RizzClaimHandoff.last, operation_id: "op-1", consumed_at: nil)
      expect(stored.receipt_digest).to eq(Digest::SHA256.hexdigest(query["receipt"]))
      expect(stored.expires_at).to be_within(5.seconds).of(60.seconds.from_now)
      expect(RizzClaimHandoff.last).to have_attributes(first_name: "Marcus", last_name: "Tate")
      expect(RizzClaimHandoff.last.consumed_at).to be_present
      expect(RizzClaimHandoff.last.encrypted_password).to match(/\A\$2/)
      expect(set_cookies).to match(/rizz_create_local=;|rizz_create_local=$/)
      expect(request.env["warden"].user(:voter)).to be_nil
    end

    it "creates a confirmed, independently usable Voter with the Rizz binding when the receipt is spent" do
      spend submit_for_receipt
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("ok" => true, "local_handle" => "@marcus_tate", "has_independent_recovery" => true)
      voter = Voter.find_by!(email: email)
      expect(voter).to have_attributes(first_name: "Marcus", last_name: "Tate", username: "marcus_tate", display_name: "Marcus Tate", provider: nil, uid: nil)
      expect(voter).to be_confirmed
      expect(voter.valid_password?("hardwood-9")).to be(true)
      expect(VoterRizzBinding.last).to have_attributes(voter_id: voter.id, rizz_sub: "pairwise-sub-1", operation_id: "op-1", status: "active", rizz_session_epoch: 3)
    end

    it "discards the held details and marks the receipt spent" do
      spend submit_for_receipt
      expect(RizzClaimHandoff.last).to have_attributes(email: nil, first_name: nil, last_name: nil, encrypted_password: nil)
      expect(RizzClaimReceipt.last.consumed_at).to be_present
    end

    it "answers a repeated exchange without creating a second Voter" do
      receipt = submit_for_receipt
      spend receipt
      exchange(receipt: receipt)
      expect(response).to have_http_status(:ok)
      expect(Voter.where(email: email).count).to eq(1)
      expect(VoterRizzBinding.count).to eq(1)
    end

    it "refuses a receipt it never issued" do
      spend submit_for_receipt
      exchange(receipt: "different-receipt")
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => "invalid_receipt")
    end

    it "gives the new Voter independent Ascent sign-in with its email and password" do
      start_create
      submit
      receipt = receipt_from_redirect
      reset!
      exchange(receipt: receipt)
      reset!

      post voter_session_path, params: { voter: { email: email, password: "hardwood-9" } }
      expect(request.env["warden"].user(:voter)).to have_attributes(email: email, username: "marcus_tate")
      expect(request.session["rizz_binding_id"]).to be_nil
      delete destroy_voter_session_path

      post voter_session_path, params: { voter: { email: email, password: "wrong-password" } }
      expect(request.env["warden"].user(:voter)).to be_nil
    end

    it "does not sign the browser in, even when it is signed in as someone else" do
      other = create(:voter)
      sign_in other
      start_create
      submit
      expect(request.env["warden"].user(:voter)).to eq(other)
      expect(other.reload).to have_attributes(email: other.email)
    end
  end

  describe "validation errors" do
    before { start_create }

    it "re-renders without spending the handoff, and a corrected retry succeeds" do
      create(:voter, username: "marcus_tate")
      submit
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Username has already been taken")
      expect(RizzClaimHandoff.last).to have_attributes(consumed_at: nil, encrypted_password: nil)
      expect(RizzClaimReceipt.count).to eq(0)
      expect(response.body).not_to include("hardwood-9")
      expect(Nokogiri::HTML(response.body).at_css("form[action='#{rizz_create_path}']")["data-turbo"]).to eq("false")

      submit voter: onboarding[:voter].merge(username: "marcus_t")
      expect(response).to have_http_status(:see_other)
      expect(response.location).to start_with(callback_uri)
    end

    {
      "a blank first name" => { first_name: " " },
      "a blank last name" => { last_name: " " },
      "a blank username" => { username: " " },
      "a blank display name" => { display_name: " " },
      "a mismatched password confirmation" => { password_confirmation: "different-1" },
      "a missing password confirmation" => { password_confirmation: nil },
      "a password shorter than Devise allows" => { password: "abc", password_confirmation: "abc" },
      "a password without its confirmation" => { password_confirmation: "" },
      "a confirmation without its password" => { password: "" },
      "a reserved username" => { username: "admin" },
      "an invalid username" => { username: "Marcus T!" }
    }.each do |description, change|
      it "rejects #{description}" do
        submit voter: onboarding[:voter].merge(change).compact
        expect(response).to have_http_status(:unprocessable_content)
        expect(RizzClaimHandoff.last.consumed_at).to be_nil
        expect(RizzClaimReceipt.count).to eq(0)
      end
    end
  end

  describe "passwordless create" do
    let(:passwordless) { { voter: { first_name: "Marcus", last_name: "Tate", username: "marcus_tate", display_name: "Marcus Tate" } } }

    def create_and_exchange(attributes)
      start_create
      submit attributes
      expect(response).to have_http_status(:see_other)
      receipt_from_redirect.tap { |receipt| reset!.then { exchange(receipt: receipt) } }
    end

    it "creates a confirmed Voter in one click when the password fields are omitted or blank, with a random internal password" do
      [ passwordless, { voter: passwordless[:voter].merge(password: "", password_confirmation: "") } ].each_with_index do |attributes, index|
        reset!
        start_create(jti: "one-click-#{index}", operation_id: "op-#{index}", email: "one.click#{index}@example.com")
        submit voter: attributes[:voter].merge(username: "one_click_#{index}")
        expect(response.location).to start_with(callback_uri)
        digest = RizzClaimHandoff.order(:created_at).last.encrypted_password
        expect(digest).to match(/\A\$2/)
        receipt = receipt_from_redirect
        reset!
        exchange(receipt: receipt, operation_id: "op-#{index}", rizz_sub: "sub-#{index}")
        expect(response).to have_http_status(:ok)
        voter = Voter.find_by!(email: "one.click#{index}@example.com")
        expect(voter).to be_confirmed
        expect(voter.valid_password?("")).to be(false)
        expect(voter.encrypted_password).to eq(digest)
      end
    end

    it "lets the Voter sign in with Google directly after the Rizz binding is disconnected" do
      create_and_exchange(passwordless)
      expect(response).to have_http_status(:ok)
      VoterRizzBinding.last.update!(status: "disconnected", disconnected_at: Time.current)
      auth = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-direct-1",
        info: { email: email, first_name: "Marcus", last_name: "Tate", email_verified: true }
      )
      voter = Voter.from_google(auth)
      expect(voter).to have_attributes(email: email, username: "marcus_tate", provider: "google_oauth2", uid: "google-direct-1")
      expect(Voter.where(email: email).count).to eq(1)
    end

    it "runs normal password validation as soon as either password field is filled (including spaces only)" do
      start_create
      [
        { password: "hardwood-9", password_confirmation: "" },
        { password: "", password_confirmation: "hardwood-9" },
        { password: "        ", password_confirmation: "        " }
      ].each do |password_attrs|
        submit voter: passwordless[:voter].merge(password_attrs)
        expect(response).to have_http_status(:unprocessable_content)
        expect(RizzClaimHandoff.last.encrypted_password).to be_nil
      end
      expect(RizzClaimReceipt.count).to eq(0)
    end

    it "opens the password section when its validation fails, and a corrected password works for direct sign-in after disconnect" do
      start_create
      submit voter: passwordless[:voter].merge(password: "abc", password_confirmation: "abc")
      expect(response).to have_http_status(:unprocessable_content)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("details[open] input[name='voter[password]']")).to be_present
      expect(RizzClaimHandoff.last).to have_attributes(consumed_at: nil, encrypted_password: nil)

      submit voter: passwordless[:voter].merge(password: "hardwood-9", password_confirmation: "different-1")
      expect(Nokogiri::HTML(response.body).at_css("details[open] input[name='voter[password_confirmation]']")).to be_present

      submit voter: passwordless[:voter].merge(password: "hardwood-9", password_confirmation: "hardwood-9")
      receipt = receipt_from_redirect
      reset!
      exchange(receipt: receipt)
      VoterRizzBinding.last.update!(status: "disconnected", disconnected_at: Time.current)
      post voter_session_path, params: { voter: { email: email, password: "hardwood-9" } }
      expect(request.env["warden"].user(:voter)).to have_attributes(email: email, username: "marcus_tate")
    end

    it "keeps the password section closed when the form re-renders for a non-password error" do
      create(:voter, username: "marcus_tate")
      start_create
      submit passwordless
      expect(response).to have_http_status(:unprocessable_content)
      expect(Nokogiri::HTML(response.body).at_css("details[open]")).to be_nil
    end
  end

  describe "handle and display name defaults" do
    it "prefills the handle from the signed username and the display name from the signed display_name" do
      start_create(username: "Marcus_T", display_name: "Marcus Tate")
      expect(RizzClaimHandoff.last).to have_attributes(suggested_username: "marcus_t", username: nil)
      get rizz_create_path
      form = Nokogiri::HTML(response.body).at_css("form[action='#{rizz_create_path}']")
      expect(form.at_css("input[name='voter[username]']")["value"]).to eq("marcus_t")
      expect(form.at_css("input[name='voter[display_name]']")["value"]).to eq("Marcus Tate")
      expect(response.body).not_to include("already taken")
    end

    it "leaves the handle empty without a suggestion" do
      start_create(username: "")
      expect(RizzClaimHandoff.last.suggested_username).to be_nil
      get rizz_create_path
      expect(Nokogiri::HTML(response.body).at_css("input[name='voter[username]']")["value"]).to be_nil
    end

    it "warns inline when the suggested handle is already taken on Ascent, in any case" do
      create(:voter, username: "marcus_t")
      start_create(username: "Marcus_T")
      get rizz_create_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("@marcus_t is already taken on Ascent")
      expect(Nokogiri::HTML(response.body).at_css("input[name='voter[username]']")["value"]).to eq("marcus_t")
    end

    it "treats rizz, micharisma, and ascent as reserved and warns about them" do
      expect(Voter::RESERVED_USERNAMES).to include("rizz", "micharisma", "ascent")
      start_create(username: "Rizz")
      get rizz_create_path
      expect(response.body).to include("@rizz is already taken")
      submit voter: { first_name: "Marcus", last_name: "Tate", username: "micharisma", display_name: "Marcus Tate" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Username is reserved")
    end

    it "rejects an invalid suggested handle at start" do
      %w[ab marcus-t].each do |username|
        start_create(username: username)
        expect(response).to redirect_to(new_voter_session_path)
      end
      expect(RizzClaimHandoff.count).to eq(0)
    end
  end

  describe "optional Google link" do
    let(:uid) { "google-link-1" }

    around do |example|
      previous = [ OmniAuth.config.test_mode, OmniAuth.config.mock_auth[:rizz_claim_google] ]
      OmniAuth.config.test_mode = true
      example.run
    ensure
      OmniAuth.config.test_mode, OmniAuth.config.mock_auth[:rizz_claim_google] = previous
    end

    def link_google(uid: self.uid, google_email: email, iat: Time.now.to_i, id_sub: uid, provider: "rizz_claim_google", verified: true)
      OmniAuth.config.mock_auth[:rizz_claim_google] = OmniAuth::AuthHash.new(
        provider: provider,
        uid: uid,
        info: { email: google_email, email_verified: verified, name: "Marcus" },
        extra: { id_info: { sub: id_sub, iat: iat }.compact }
      )
      post "/auth/rizz/claim/google"
      expect(response).to redirect_to("http://www.example.com/auth/rizz/claim/google/callback")
      follow_redirect!
    end

    it "offers a prominent Link Google now button outside the form that reuses the claim Google path, and hides it when Google is off" do
      start_create
      get rizz_create_path
      page = Nokogiri::HTML(response.body)
      expect(page.css("details form[action='/auth/rizz/claim/google']")).to be_empty
      expect(page.at_css("form[action='#{rizz_create_path}']").at_css("form[action='/auth/rizz/claim/google']")).to be_nil
      button_form = page.at_css("form[action='/auth/rizz/claim/google']")
      expect(button_form["method"]).to eq("post")
      expect(button_form["data-turbo"]).to eq("false")
      expect(button_form.at_css("button.google-sign-in, button.auth-google")).to be_present
      expect(button_form.at_css("button, input[type=submit]").then { it["value"] || it.text.strip }).to eq("Link Google account now")

      allow(Voter).to receive(:google_sign_in_available?).and_return(false)
      get rizz_create_path
      expect(response.body).not_to include("Link Google")
    end

    it "binds a verified matching Google account to the handoff without creating or signing in a Voter, then to the Voter at exchange" do
      expect(Voter).not_to receive(:from_google)
      start_create
      expect { link_google }.not_to change(Voter, :count)
      expect(response).to redirect_to(rizz_create_path)
      expect(flash[:notice]).to eq("Google account verified and will be linked when you create your account.")
      expect(RizzClaimHandoff.last).to have_attributes(google_uid: uid, intent: "create", consumed_at: nil)
      expect(request.env["warden"].user(:voter)).to be_nil

      follow_redirect!
      expect(response.body).to include("Google account verified — will be linked for direct sign-in.")
      expect(response.body).not_to include("Link Google account now")

      submit
      receipt = receipt_from_redirect
      reset!
      exchange(receipt: receipt)
      expect(response).to have_http_status(:ok)
      expect(Voter.find_by!(email: email)).to have_attributes(provider: "google_oauth2", uid: uid)
      expect(RizzClaimHandoff.last.google_uid).to be_nil
    end

    it "lets a Voter created with a linked Google account sign in with Google after Rizz is disconnected" do
      start_create
      link_google
      submit voter: onboarding[:voter].except(:password, :password_confirmation)
      receipt = receipt_from_redirect
      reset!
      exchange(receipt: receipt)
      VoterRizzBinding.last.update!(status: "disconnected", disconnected_at: Time.current)
      auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: uid, info: { email: email, first_name: "Marcus", last_name: "Tate", email_verified: true })
      expect(Voter.from_google(auth)).to eq(Voter.find_by!(email: email))
    end

    it "rejects a Google account for another email and links nothing" do
      start_create
      link_google(google_email: "someone.else@gmail.com")
      expect(response).to redirect_to(rizz_create_path)
      expect(flash[:alert]).to eq("Choose the Google account matching #{RizzSignIn.mask_email(email)}, or create your account without linking Google now.")
      expect(RizzClaimHandoff.last.google_uid).to be_nil
      expect(Voter.count).to eq(0)
    end

    it "matches the Google email regardless of case and whitespace" do
      start_create
      link_google(google_email: " Marcus.Tate@GMAIL.com ")
      expect(RizzClaimHandoff.last.google_uid).to eq(uid)
    end

    {
      "a stale iat" => { iat: 10.minutes.ago.to_i },
      "a missing iat" => { iat: nil },
      "a mismatched id token subject" => { id_sub: "someone-else" },
      "another provider" => { provider: "google_oauth2" },
      "an unverified email" => { verified: false }
    }.each do |description, options|
      it "does not link a Google proof with #{description}" do
        start_create
        link_google(**options)
        expect(response).to redirect_to(rizz_create_path)
        expect(flash[:alert]).to be_present
        expect(RizzClaimHandoff.last.google_uid).to be_nil
        expect(Voter.count).to eq(0)
      end
    end

    it "steers a matching-email Google account whose subject already belongs to a Voter to Claim, never calling Voter.from_google" do
      expect(Voter).not_to receive(:from_google)
      start_create
      owner = create(:voter, username: "ballot_marcus", email: email, provider: "google_oauth2", uid: uid)
      expect { link_google(google_email: email) }.not_to change(Voter, :count)
      expect(response).to redirect_to(rizz_claim_prove_path)
      expect(flash[:notice]).to eq("That Google account already belongs to an Ascent account. Confirm it's you to connect it.")
      expect(RizzClaimHandoff.last).to have_attributes(
        intent: "claim",
        email: nil,
        first_name: nil,
        last_name: nil,
        username: nil,
        display_name: nil,
        encrypted_password: nil,
        suggested_username: nil,
        google_uid: nil,
        verified_voter_id: nil
      )
      expect(set_cookies).to match(/rizz_claim_local=[^;]/)
      expect(owner.reload.uid).to eq(uid)
      expect(owner.active_rizz_binding).to be_nil

      get rizz_create_path
      expect(response).to redirect_to(new_voter_session_path)
      get rizz_claim_prove_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Marcus T. (Rizz)")
    end

    it "rejects a wrong-email Google account linked to another Voter without converting Create to Claim" do
      create(:voter, username: "ballot_other", email: "other@example.com", provider: "google_oauth2", uid: uid)
      start_create
      expect { link_google(google_email: "other@example.com") }.not_to change(Voter, :count)
      expect(response).to redirect_to(rizz_create_path)
      expect(flash[:alert]).to eq("Choose the Google account matching #{RizzSignIn.mask_email(email)}, or create your account without linking Google now.")
      expect(RizzClaimHandoff.last).to have_attributes(intent: "create", email: email, google_uid: nil, verified_voter_id: nil)
      get rizz_create_path
      expect(response).to have_http_status(:ok)
    end

    it "returns to the Create form when Google is cancelled, and to the claim proof for a claim browser" do
      start_create
      OmniAuth.config.mock_auth[:rizz_claim_google] = :access_denied
      post "/auth/rizz/claim/google"
      follow_redirect!
      expect(response).to redirect_to(rizz_create_path)
      expect(RizzClaimHandoff.last.google_uid).to be_nil

      reset!
      post rizz_claim_start_path, params: { handoff: speaker.claim_handoff(callback_uri: callback_uri) }
      post "/auth/rizz/claim/google"
      follow_redirect!
      expect(response).to redirect_to(rizz_claim_prove_path)

      reset!
      post "/auth/rizz/claim/google"
      follow_redirect!
      expect(response).to redirect_to(rizz_claim_prove_path)
    end

    it "refuses the Google callback without either cookie, or with a cookie that does not match" do
      start_create
      attacker = open_session
      OmniAuth.config.mock_auth[:rizz_claim_google] = OmniAuth::AuthHash.new(
        provider: "rizz_claim_google",
        uid: uid,
        info: { email: email, email_verified: true },
        extra: { id_info: { sub: uid, iat: Time.now.to_i } }
      )
      attacker.post "/auth/rizz/claim/google"
      attacker.follow_redirect!
      expect(redirect_path(attacker)).to eq(new_voter_session_path)
      expect(RizzClaimHandoff.last.google_uid).to be_nil

      RizzClaimHandoff.last.update!(browser_token_digest: RizzClaimHandoff.digest("another browser"))
      post "/auth/rizz/claim/google"
      follow_redirect!
      expect(response).to redirect_to(new_voter_session_path)
      expect(RizzClaimHandoff.last.google_uid).to be_nil
    end

    it "does not attach Google to an expired or spent handoff" do
      start_create
      handoff = RizzClaimHandoff.last
      handoff.update!(expires_at: 1.second.ago)
      link_google
      expect(response).to redirect_to(new_voter_session_path)
      expect(handoff.reload.google_uid).to be_nil

      reset!
      start_create(jti: "spent-handoff")
      spent = RizzClaimHandoff.last
      spent.consume!
      link_google
      expect(response).to redirect_to(new_voter_session_path)
      expect(spent.reload.google_uid).to be_nil
    end

    it "switches to the claim when the linked Google account is taken before the form is submitted" do
      start_create
      link_google
      create(:voter, provider: "google_oauth2", uid: uid)
      expect { submit }.not_to change(Voter, :count)
      expect(response).to redirect_to(rizz_claim_prove_path)
      expect(RizzClaimHandoff.last).to have_attributes(intent: "claim", google_uid: nil, suggested_username: nil, email: nil, first_name: nil, last_name: nil, consumed_at: nil)
      expect(RizzClaimReceipt.count).to eq(0)
    end

    it "answers 409 email_taken and creates nothing when the linked Google account is taken after the receipt" do
      start_create
      link_google
      submit
      receipt = receipt_from_redirect
      reset!
      create(:voter, provider: "google_oauth2", uid: uid)
      expect { exchange(receipt: receipt) }.not_to change(Voter, :count)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "email_taken")
      expect(VoterRizzBinding.count).to eq(0)
      expect(RizzClaimReceipt.last.consumed_at).to be_nil
    end

    it "answers 409 when the unique index rejects a Google account that validation did not see" do
      start_create
      link_google
      submit
      receipt = receipt_from_redirect
      reset!
      create(:voter, provider: "google_oauth2", uid: uid)
      allow_any_instance_of(Voter).to receive(:valid?).and_return(true)
      expect { exchange(receipt: receipt) }.not_to change(Voter, :count)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "email_taken")
      expect(VoterRizzBinding.count).to eq(0)
    end

    it "clears first_name, last_name, google_uid, and suggested_username on cancel, discard, purge and switch" do
      start_create(username: "marcus_t")
      link_google
      handoff = RizzClaimHandoff.last
      handoff.update!(first_name: "Marcus", last_name: "Tate")
      post rizz_create_cancel_path
      expect(handoff.reload).to have_attributes(first_name: nil, last_name: nil, google_uid: nil, suggested_username: nil, email: nil)

      handoff.update!(email: email, first_name: "Marcus", last_name: "Tate", google_uid: uid, suggested_username: "marcus_t")
      handoff.discard_draft!
      expect(handoff.reload).to have_attributes(first_name: nil, last_name: nil, google_uid: nil, suggested_username: nil)

      handoff.update!(email: email, first_name: "Marcus", last_name: "Tate", google_uid: uid, suggested_username: "marcus_t", consumed_at: nil, expires_at: 1.second.ago)
      RizzClaimHandoff.purge_spent_drafts!
      expect(handoff.reload).to have_attributes(first_name: nil, last_name: nil, google_uid: nil, suggested_username: nil, email: nil)

      handoff.update!(intent: "create", email: email, first_name: "Marcus", last_name: "Tate", username: "marcus_t", encrypted_password: "digest", google_uid: uid, suggested_username: "marcus_t")
      handoff.switch_to_claim!
      expect(handoff.reload).to have_attributes(intent: "claim", email: nil, first_name: nil, last_name: nil, username: nil, encrypted_password: nil, google_uid: nil, suggested_username: nil)

      handoff.update!(first_name: "Marcus", last_name: "Tate", username: "marcus_t", encrypted_password: "digest", consumed_at: 2.minutes.ago)
      RizzClaimHandoff.purge_spent_drafts!
      expect(handoff.reload).to have_attributes(first_name: nil, last_name: nil, username: nil, encrypted_password: nil)
    end
  end

  describe "cookie exclusivity" do
    it "clears the Create cookie when a Claim starts, and clears the Claim cookie when a Create starts" do
      start_create
      post rizz_claim_start_path, params: { handoff: speaker.claim_handoff(callback_uri: callback_uri, jti: "claim-after-create") }
      expect(set_cookies).to match(/rizz_create_local=;|rizz_create_local=$/m)
      expect(set_cookies).to match(/rizz_claim_local=[^;\s]/)
      get rizz_create_path
      expect(response).to redirect_to(new_voter_session_path)
      get rizz_claim_prove_path
      expect(response).to have_http_status(:ok)

      start_create(jti: "create-after-claim")
      expect(set_cookies).to match(/rizz_claim_local=;|rizz_claim_local=$/m)
      expect(set_cookies).to match(/rizz_create_local=[^;\s]/)
      get rizz_claim_prove_path
      expect(response).to redirect_to(new_voter_session_path)
      get rizz_create_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "an email that already has a Voter" do
    let!(:existing) { create(:voter, email: email, username: "ballot_marcus", provider: nil, uid: nil) }

    def expect_claim_proof_without_changes
      expect(response).to redirect_to(rizz_claim_prove_path)
      expect(existing.reload).to have_attributes(provider: nil, uid: nil, username: "ballot_marcus", confirmed_at: existing.confirmed_at, unconfirmed_email: nil)
      expect(existing.valid_password?("password123")).to be(true)
      expect(VoterRizzBinding.count).to eq(0)
      expect(RizzClaimReceipt.count).to eq(0)
    end

    it "at start continues as a claim handoff, without linking, emailing, or modifying the Voter" do
      expect { start_create }.not_to change(Voter, :count)
      expect_claim_proof_without_changes
      expect(RizzClaimHandoff.last).to have_attributes(intent: "claim", email: nil, verified_voter_id: nil)
      expect(set_cookies).to match(/rizz_claim_local=/)
      follow_redirect!
      expect(response.body).to include("Confirm with password", "Marcus T. (Rizz)")
      expect(request.env["warden"].user(:voter)).to be_nil

      post rizz_claim_verify_password_path, params: { email: email, password: "password123" }
      expect(response).to redirect_to(rizz_claim_confirm_path)
    end

    it "matches the email regardless of case" do
      start_create(email: "Marcus.Tate@GMAIL.com")
      expect_claim_proof_without_changes
    end

    it "switches the handoff to a claim on submit if the email appears after the form was shown" do
      other_email = "late.arrival@example.com"
      start_create(email: other_email)
      late = create(:voter, email: other_email)
      expect { submit }.not_to change(Voter, :count)
      expect(response).to redirect_to(rizz_claim_prove_path)
      expect(set_cookies).to match(/rizz_claim_local=/)
      expect(RizzClaimHandoff.last).to have_attributes(intent: "claim", email: nil, encrypted_password: nil, consumed_at: nil)
      expect(RizzClaimReceipt.count).to eq(0)
      get rizz_claim_confirm_path
      expect(response).to redirect_to(rizz_claim_prove_path)
      expect(late.reload.active_rizz_binding).to be_nil
    end

    it "keeps returning 409 email_taken on retry when the email is taken after the receipt" do
      other_email = "last.second@example.com"
      start_create(email: other_email)
      submit
      receipt = receipt_from_redirect
      reset!
      late = create(:voter, email: other_email, username: "first_to_arrive")
      exchange(receipt: receipt)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "email_taken")
      expect(Voter.where(email: other_email)).to contain_exactly(late)
      expect(VoterRizzBinding.count).to eq(0)
      expect(RizzClaimReceipt.last.consumed_at).to be_nil

      exchange(receipt: receipt)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "email_taken")
    end

    it "answers 409 email_taken when the email index rejects an insert that validation did not see" do
      other_email = "index.race@example.com"
      start_create(email: other_email)
      submit
      receipt = receipt_from_redirect
      reset!
      racing = create(:voter, email: other_email, username: "first_to_arrive")
      allow_any_instance_of(Voter).to receive(:valid?).and_return(true)
      exchange(receipt: receipt)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "email_taken")
      expect(Voter.where(email: other_email)).to contain_exactly(racing)
      expect(VoterRizzBinding.count).to eq(0)
    end

    it "returns plain 409 conflict when the handle is taken after the receipt" do
      start_create(email: "new.handle@example.com")
      submit
      receipt = receipt_from_redirect
      reset!
      create(:voter, username: "marcus_tate")
      exchange(receipt: receipt)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "conflict")
      expect(Voter.where(email: "new.handle@example.com")).to be_empty
      expect(VoterRizzBinding.count).to eq(0)
    end
  end

  describe "separation, browser binding, rollback, and purge" do
    it "refuses every claim step with a create cookie, and every create step with a claim cookie" do
      start_create
      handoff = RizzClaimHandoff.last
      [
        [ :get, rizz_claim_prove_path ],
        [ :get, rizz_claim_confirm_path ],
        [ :post, rizz_claim_confirm_path ],
        [ :post, rizz_claim_verify_password_path, { email: "x@example.com", password: "password123" } ]
      ].each do |verb, path, params|
        public_send(verb, path, params: params)
        expect(response).to redirect_to(new_voter_session_path), "#{verb} #{path}"
      end

      reset!
      post rizz_claim_start_path, params: { handoff: speaker.claim_handoff(callback_uri: callback_uri) }
      get rizz_create_path
      expect(response).to redirect_to(new_voter_session_path)
      submit
      expect(response).to redirect_to(new_voter_session_path)
      expect(RizzClaimReceipt.count).to eq(0)
      expect(handoff.reload.consumed_at).to be_nil
    end

    it "refuses onboarding without the cookie that started it" do
      start_create
      attacker = open_session
      attacker.get rizz_create_path
      expect(redirect_path(attacker)).to eq(new_voter_session_path)
      attacker.post rizz_create_path, params: onboarding
      expect(redirect_path(attacker)).to eq(new_voter_session_path)
      expect(RizzClaimReceipt.count).to eq(0)
    end

    it "rolls the whole onboarding back when the receipt cannot be issued, and rolls the exchange back when binding fails" do
      start_create
      allow(RizzClaimReceipt).to receive(:issue!).and_raise(ActiveRecord::StatementInvalid)
      expect { submit }.to raise_error(ActiveRecord::StatementInvalid)
      expect(RizzClaimHandoff.last).to have_attributes(consumed_at: nil, encrypted_password: nil, username: nil)

      allow(RizzClaimReceipt).to receive(:issue!).and_call_original
      submit
      receipt = receipt_from_redirect
      reset!
      allow(VoterRizzBinding).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      exchange(receipt: receipt)
      expect(response).to have_http_status(:conflict)
      expect(Voter.where(email: email)).to be_empty
      expect(RizzClaimReceipt.last.consumed_at).to be_nil
      expect(RizzClaimHandoff.last.encrypted_password).to be_present
    end

    it "returns gone instead of raising if a receipt for the same operation_id already exists" do
      start_create
      handoff = RizzClaimHandoff.last
      RizzClaimReceipt.issue!(voter: create(:voter), operation_id: handoff.operation_id)

      result = RizzSignIn::Onboarding.call(handoff: handoff, attributes: onboarding[:voter].stringify_keys)
      expect(result.status).to eq(:gone)
      expect(handoff.reload.consumed_at).to be_nil
    end

    it "purges abandoned digests whenever another handoff starts, and schedules purge in recurring.yml" do
      start_create
      submit
      receipt = receipt_from_redirect
      reset!
      RizzClaimHandoff.last.update!(consumed_at: 2.minutes.ago)
      RizzClaimReceipt.last.update!(expires_at: 1.minute.from_now)
      start_create(jti: "another")
      expect(RizzClaimHandoff.where.not(encrypted_password: nil)).to be_empty
      exchange(receipt: receipt)
      expect(response).to have_http_status(:bad_request)
      expect(Voter.where(email: email)).to be_empty

      recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true).dig("production", "rizz_onboarding_digests")
      expect(recurring).to include("command" => "RizzClaimHandoff.purge_spent_drafts!")
    end

    it "returns 404 for every create endpoint when disabled" do
      with_rizz_env("RIZZ_SIGN_IN_ENABLED" => "0") do
        post "/auth/rizz/create/start", params: { handoff: "x" }
        expect(response).to have_http_status(:not_found)
        get "/auth/rizz/create"
        expect(response).to have_http_status(:not_found)
        post "/auth/rizz/create"
        expect(response).to have_http_status(:not_found)
        post "/auth/rizz/create/cancel"
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
