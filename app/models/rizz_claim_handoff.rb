# frozen_string_literal: true

# A verified Speaker handoff, held server-side while the browser either proves it controls a local Voter
# (intent "claim") or finishes onboarding a new one (intent "create"). The browser only carries a token
# matching browser_token_digest.
#
# A create handoff holds the verified Google email, suggested display name and optional suggested handle the Speaker
# signed, plus the Google subject the browser optionally proved. Onboarding stores the chosen name, username,
# display name and a bcrypt digest of the chosen (or generated) password here; the Voter itself is built only when
# the Speaker spends the receipt (RizzSignIn::ClaimExchange), so a handoff replayed in another browser can never
# provision an account. A create handoff becomes a claim handoff when its email already belongs to a Voter.
class RizzClaimHandoff < ApplicationRecord
  PROOF_WINDOW = 5.minutes
  LIFETIME = 10.minutes
  SPEAKER_LABEL_MAX = 120
  INTENTS = %w[claim create].freeze

  belongs_to :verified_voter, class_name: "Voter", optional: true

  validates :handoff_jti, :operation_id, :speaker_label, :callback_uri, :browser_token_digest, :expires_at, presence: true
  validates :intent, inclusion: { in: INTENTS }
  validates :email, presence: true, if: :create_intent?

  INTENTS.each do |name|
    define_method(:"#{name}_intent?") { intent == name }
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # Whether a verified handoff's callback is the issuer's own origin and its label fits the confirmation page.
  def self.acceptable?(claims)
    RizzSignIn.configuration.issuer_origin?(claims["callback_uri"]) && claims["speaker_label"].length <= SPEAKER_LABEL_MAX
  end

  # Persists a verified handoff and returns it with the random token the browser keeps in its cookie.
  # A create handoff never outlives the Speaker's signed exp.
  def self.start!(claims, intent: "claim", expires_at: LIFETIME.from_now)
    token = SecureRandom.urlsafe_base64(32)
    create_attributes = if intent == "create"
      claims.slice("email", "display_name").symbolize_keys.merge(suggested_username: claims["username"])
    else
      {}
    end
    handoff = create!({
      handoff_jti: claims["jti"],
      operation_id: claims["operation_id"],
      speaker_label: claims["speaker_label"],
      callback_uri: claims["callback_uri"],
      browser_token_digest: digest(token),
      expires_at: expires_at,
      intent: intent
    }.merge(create_attributes))
    [ handoff, token ]
  end

  # A spent handoff can still have a redeemable receipt after the handoff expires.
  def self.purge_spent_drafts!
    stale = where(consumed_at: nil, expires_at: ..Time.current)
      .or(where(consumed_at: ...(RizzClaimReceipt::LIFETIME + 5.seconds).ago))
    with_draft_data = where.not(email: nil)
      .or(where.not(first_name: nil))
      .or(where.not(last_name: nil))
      .or(where.not(display_name: nil))
      .or(where.not(encrypted_password: nil))
      .or(where.not(google_uid: nil))
      .or(where.not(username: nil))
      .or(where.not(suggested_username: nil))
    stale.merge(with_draft_data).update_all(
      email: nil,
      first_name: nil,
      last_name: nil,
      username: nil,
      display_name: nil,
      encrypted_password: nil,
      suggested_username: nil,
      google_uid: nil
    )
  end

  def return_url(receipt)
    "#{callback_uri}#{callback_uri.include?("?") ? "&" : "?"}#{{ operation_id: operation_id, receipt: receipt }.to_query}"
  end

  def usable?
    consumed_at.nil? && expires_at.future?
  end

  def proven?
    verified_voter_id.present? && verified_at.present? && verified_at > PROOF_WINDOW.ago
  end

  def prove!(voter)
    update!(verified_voter: voter, verified_at: Time.current)
  end

  def suggested_name_parts
    parts = display_name.to_s.strip.split(/\s+/)
    return [ "", "" ] if parts.empty?
    return [ parts.first, "" ] if parts.one?

    [ parts.first, parts[1..].join(" ") ]
  end

  def onboard!(voter)
    update!(
      first_name: voter.first_name,
      last_name: voter.last_name,
      username: voter.username,
      display_name: voter.display_name,
      encrypted_password: voter.encrypted_password
    )
  end

  # The confirmed Voter onboarding described. Its email comes only from the verified handoff.
  def build_voter
    google_attributes = google_uid.present? ? { provider: "google_oauth2", uid: google_uid } : {}
    Voter.build_with_password_digest(
      encrypted_password,
      email: email,
      first_name: first_name,
      last_name: last_name,
      username: username,
      display_name: display_name,
      **google_attributes
    )
  end

  def discard_draft!
    update_columns(
      email: nil,
      first_name: nil,
      last_name: nil,
      username: nil,
      display_name: nil,
      encrypted_password: nil,
      suggested_username: nil,
      google_uid: nil
    )
  end

  def cancel_create!
    with_lock { discard_draft! if consume! }
  end

  # A create handoff whose email turned out to belong to a Voter continues as an ordinary claim: no proof carries over.
  def switch_to_claim!
    update!(
      intent: "claim",
      email: nil,
      first_name: nil,
      last_name: nil,
      username: nil,
      display_name: nil,
      encrypted_password: nil,
      suggested_username: nil,
      google_uid: nil,
      verified_voter: nil,
      verified_at: nil
    )
  end

  # Atomic: only one caller can spend the handoff.
  def consume!
    self.class.where(id: id, consumed_at: nil).where("expires_at > ?", Time.current).update_all(consumed_at: Time.current, updated_at: Time.current) == 1
  end
end
