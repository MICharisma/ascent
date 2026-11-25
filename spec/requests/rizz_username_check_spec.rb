# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rizz username check", type: :request do
  include_context "with a Rizz speaker"

  def check_username(username, headers: rizz_basic_auth)
    post "/auth/rizz/usernames/check",
      params: { username: username }.to_json,
      headers: headers.merge("Content-Type" => "application/json")
  end

  it "returns available: true for an unused valid handle and sends Cache-Control: no-store" do
    check_username("  Maya_Rizz7 ")
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.parsed_body).to eq(
      "username" => "maya_rizz7",
      "status" => "available",
      "available" => true
    )
  end

  it "returns taken case-insensitively without leaking any account details" do
    create(:voter, first_name: "Maya", last_name: "Ortiz", username: "maya_rizz", email: "maya@example.com")
    check_username("Maya_Rizz")
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.parsed_body).to eq(
      "username" => "maya_rizz",
      "status" => "taken",
      "available" => false
    )
  end

  it "returns reserved for reserved usernames" do
    check_username("Ascent")
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "username" => "ascent",
      "status" => "reserved",
      "available" => false
    )
  end

  it "returns 422 invalid for malformed, short, long, or non-string inputs" do
    [ "", "ab", "a" * 25, "maya-rizz!", 123, nil ].each do |bad|
      check_username(bad)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.parsed_body).to include("status" => "invalid", "available" => false)
    end
  end

  it "requires valid HTTP Basic client credentials" do
    post "/auth/rizz/usernames/check",
      params: { username: "maya_rizz" }.to_json,
      headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)

    check_username("maya_rizz", headers: rizz_basic_auth(secret: "wrong-secret"))
    expect(response).to have_http_status(:unauthorized)
  end

  it "supports the dedicated RIZZ_CLAIM_EXCHANGE_SECRET" do
    with_rizz_env("RIZZ_CLAIM_EXCHANGE_SECRET" => "exchange-secret") do
      check_username("maya_rizz", headers: rizz_basic_auth(secret: "exchange-secret"))
      expect(response).to have_http_status(:ok)

      check_username("maya_rizz", headers: rizz_basic_auth)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "returns 404 when RIZZ_SIGN_IN_ENABLED is disabled" do
    with_rizz_env("RIZZ_SIGN_IN_ENABLED" => "0") do
      check_username("maya_rizz")
      expect(response).to have_http_status(:not_found)
    end
  end
end
