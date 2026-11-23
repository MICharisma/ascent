require 'rails_helper'

# Google sign-in finds the voter linked to the Google account, links a voter with the same verified
# email, or makes a new confirmed voter, and turns away an email Google has not verified.
RSpec.describe "Google sign-in", type: :request do
  def google_account(email: "rosa.delgado@example.com", verified: true, uid: "google-uid-1081")
    OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid,
      info: { email: email, first_name: "Rosa", last_name: "Delgado", email_verified: verified },
      extra: { raw_info: { email_verified: verified } }
    )
  end

  def sign_in_with(account)
    OmniAuth.config.mock_auth[:google_oauth2] = account
    post voter_google_oauth2_omniauth_authorize_path
    follow_redirect!
  end

  around do |example|
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  it "offers Google on the sign-in and sign-up pages" do
    get new_voter_session_path
    expect(response.body).to include("Continue with Google")

    get new_voter_registration_path
    expect(response.body).to include("Continue with Google")
  end

  it "shows the branded Google button in the top navigation when enabled, falling back to Sign Up when disabled" do
    get issues_path
    doc = Nokogiri::HTML(response.body)
    nav_auth = doc.at_css(".nav-auth .devise-links")
    expect(nav_auth).to be_present
    form = nav_auth.at_css("form.google-sign-in-form")
    expect(form).to be_present
    expect(form["data-turbo"]).to eq("false")
    expect(form["action"]).to eq(voter_google_oauth2_omniauth_authorize_path(origin: issues_path))
    button = form.at_css("button.google-sign-in")
    expect(button["aria-label"]).to eq("Get In with Google to Ascent")
    expect(button.text).to include("Get In")
    expect(button.at_css("img[src='/google-g.png']")).to be_present
    expect(button.at_css("img.google-sign-in-site[src='/icon.svg']")).to be_present
    expect(nav_auth.at_css(".sign-up-link")).to be_nil

    allow(Voter).to receive(:google_sign_in_available?).and_return(false)
    get issues_path
    fallback_nav = Nokogiri::HTML(response.body).at_css(".nav-auth .devise-links")
    expect(fallback_nav.at_css("button.google-sign-in")).to be_nil
    expect(fallback_nav.at_css(".sign-in-link")).to be_present
    expect(fallback_nav.at_css(".sign-up-link")).to be_present
  end

  it "makes a confirmed voter from a new Google account and signs them in" do
    expect { sign_in_with(google_account) }.to change(Voter, :count).by(1)

    voter = Voter.find_by!(email: "rosa.delgado@example.com")
    expect(voter).to have_attributes(provider: "google_oauth2", uid: "google-uid-1081", first_name: "Rosa", last_name: "Delgado")
    expect(voter).to be_confirmed
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Hello, Rosa")
  end

  it "links an existing voter with the same verified email instead of making another" do
    voter = create(:voter, email: "Rosa.Delgado@example.com", confirmed_at: nil)

    expect { sign_in_with(google_account) }.not_to change(Voter, :count)

    expect(voter.reload).to have_attributes(provider: "google_oauth2", uid: "google-uid-1081")
    expect(voter).to be_confirmed
  end

  it "signs a linked voter back in by their Google account, even after their email changes" do
    voter = create(:voter, email: "rosa.new@example.com", provider: "google_oauth2", uid: "google-uid-1081")

    expect { sign_in_with(google_account) }.not_to change(Voter, :count)

    follow_redirect!
    expect(response.body).to include("Hello, #{voter.first_name}")
  end

  it "turns away an email Google has not verified" do
    create(:voter, email: "rosa.delgado@example.com")

    expect { sign_in_with(google_account(verified: false)) }.not_to change(Voter, :count)

    expect(response).to redirect_to(new_voter_registration_path)
    expect(Voter.find_by!(email: "rosa.delgado@example.com").uid).to be_nil
  end

  it "returns to the styled login page when Google authorization fails" do
    expect { sign_in_with(:access_denied) }.not_to change(Voter, :count)

    expect(response).to redirect_to(new_voter_session_path)
    follow_redirect!
    expect(response.body).to include("Google sign-in did not finish. Please try again.")
    expect(Nokogiri::HTML(response.body).at_css(".auth-shell h1").text).to eq("Log in")
  end

  it "records an invite for a new Google signup" do
    inviter = create(:voter)
    get invite_path(token: inviter.invite_token)

    expect { sign_in_with(google_account) }.to change(Invite, :count).by(1)

    expect(Voter.find_by!(email: "rosa.delgado@example.com").inviters).to contain_exactly(inviter)
  end

  it "does not attribute an existing Google account to a new inviter" do
    inviter = create(:voter)
    voter = create(:voter, email: "rosa.delgado@example.com")
    get invite_path(token: inviter.invite_token)

    expect { sign_in_with(google_account) }.not_to change(Invite, :count)

    expect(voter.reload.received_invites).to be_empty
    expect(response).to redirect_to(root_path)
  end

  it "retains an invite after Google authorization fails" do
    inviter = create(:voter)
    get invite_path(token: inviter.invite_token)
    sign_in_with(:access_denied)

    expect { sign_in_with(google_account) }.to change(Invite, :count).by(1)

    expect(Voter.find_by!(email: "rosa.delgado@example.com").inviters).to contain_exactly(inviter)
  end
end
