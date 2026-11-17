class Voter < ApplicationRecord
  # Include default devise modules. Others available are:
  # :registerable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :confirmable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  has_secure_token :invite_token, on: :initialize
  has_many :invites, foreign_key: :inviter_id, inverse_of: :inviter, dependent: :destroy
  has_many :invited_voters, through: :invites, source: :invitee
  has_many :received_invites, class_name: "Invite", foreign_key: :invitee_id, inverse_of: :invitee, dependent: :destroy
  has_many :inviters, through: :received_invites, source: :inviter
  has_many :voter_links, -> { ordered }, dependent: :destroy, inverse_of: :voter
  has_many :voter_statements, -> { ordered }, dependent: :destroy, inverse_of: :voter

  has_many :ahoy_visits, class_name: "Ahoy::Visit", foreign_key: :user_id, dependent: :nullify
  has_many :ahoy_events, class_name: "Ahoy::Event", foreign_key: :user_id, dependent: :nullify
  has_many :residences, dependent: :destroy
  has_many :jurisdictions, through: :residences
  has_many :ratings, dependent: :destroy
  has_many :rating_archives, dependent: :delete_all
  has_many :voter_race_baselines, dependent: :destroy
  has_many :voter_race_baseline_archives, dependent: :delete_all
  has_many :engagements, dependent: :destroy
  has_many :voter_race_preferences, dependent: :delete_all
  has_many :mountain_drafts, dependent: :delete_all
  has_many :public_mountains, dependent: :destroy
  has_many :created_elections, class_name: "Election", foreign_key: :creator_id, inverse_of: :creator, dependent: :nullify
  has_many :reviewed_channels, class_name: "Channel", foreign_key: :reviewed_by_id, dependent: :nullify

  ROLES = %w[admin moderator reviewer].freeze

  enum :role, ROLES.index_with(&:itself), validate: { allow_nil: true }

  validates :first_name, presence: true
  validates :last_name, presence: true
  # validates :is_verified, inclusion: { in: [true, false] }

  scope :publicly_visible, -> { where(profile_hidden: false) }
  scope :visible_to, ->(viewer) {
    viewer ? where(profile_hidden: false).or(where(id: viewer.id)) : publicly_visible
  }
  scope :influencers, -> { where(id: Invite.select(:inviter_id)) }
  scope :with_invite_counts, -> {
    select("voters.*, (SELECT COUNT(*) FROM invites WHERE invites.inviter_id = voters.id) AS invite_count")
  }

  scope :with_voting_activity, -> {
    includes(:ratings, :voter_race_baselines,
             ratings: { candidacy: { race: [ :election, { office: :position } ] } },
             voter_race_baselines: { race: [ :election, { office: :position } ] })
  }
  scope :with_residence_details, -> { includes(residences: :jurisdiction) }

  def self.google_sign_in_available?
    Devise.omniauth_configs.key?(:google_oauth2)
  end

  # The voter a Google account signs in as: the one already linked to it, else the one with its
  # verified email, which it then links, else a new confirmed voter with a random password.
  # Returns an unsaved voter with errors when none can be made.
  def self.from_google(auth, inviter: nil)
    find_by(provider: auth.provider, uid: auth.uid) || link_google(auth) || create_from_google(auth, inviter: inviter)
  end

  def self.link_google(auth)
    return unless google_email_verified?(auth)

    find_by(email: auth.info.email.downcase)&.tap do |voter|
      voter.skip_reconfirmation!
      voter.confirm unless voter.confirmed?
      voter.update!(provider: auth.provider, uid: auth.uid)
    end
  end

  def self.create_from_google(auth, inviter: nil)
    voter = new(provider: auth.provider, uid: auth.uid, email: auth.info.email,
                first_name: auth.info.first_name, last_name: auth.info.last_name,
                password: Devise.friendly_token(32))
    unless google_email_verified?(auth)
      voter.errors.add(:email, "is not verified with Google")
      return voter
    end

    voter.received_invites.build(inviter: inviter) if inviter
    voter.skip_confirmation!
    voter.save
    voter
  end

  def self.google_email_verified?(auth)
    auth.extra&.raw_info&.email_verified == true || auth.info.email_verified == true
  end
  private_class_method :link_google, :create_from_google, :google_email_verified?

  def admin=(value)
    self.role = ActiveModel::Type::Boolean.new.cast(value) ? "admin" : (admin? ? nil : role)
  end

  def can_moderate?
    admin? || moderator?
  end

  def can_review?
    admin? || moderator? || reviewer?
  end

  def publicly_visible_to?(viewer)
    !profile_hidden? || viewer == self
  end

  def full_name
    [ first_name, last_name ].compact.join(" ")
  end

  def name
    full_name
  end

  def race_preference(race)
    voter_race_preferences.find_by(race: race) || VoterRacePreference.new(voter: self, race: race)
  end

  # Whether this voter also rates the candidates the race's primaries eliminated; off by default.
  def includes_primary_candidates?(race)
    race_preference(race).include_primary_candidates?
  end

  def include_primary_candidates!(race, included)
    race_preference(race).update!(include_primary_candidates: included)
  end

  # Everywhere this voter lives now; they may live in several places at once.
  def current_residences
    residences.current.chronological
  end

  # The newest of the places this voter lives now, for when one name is enough.
  def current_residence
    current_residences.first
  end

  # Every jurisdiction whose offices are on this voter's ballot, across all the places they live.
  def ballot_jurisdictions
    Residence.ballot_jurisdictions(current_residences)
  end

  # Adds the given town, with its county and districts ({ "county" => ..., "congressional" => ... }), to
  # where this voter lives now.
  # Moving there ends the other current residences today; otherwise the voter lives in both. Their saved
  # mountains are then re-sorted into resident or visitor for where they live.
  def claim_residence!(jurisdiction, areas: {}, moving: true)
    transaction do
      residences.current.update_all(status: "moved", ended_on: Date.current) if moving
      residence = residences.create!(jurisdiction: jurisdiction, **area_slots(areas), status: "active",
        started_on: Date.current, registered_at: Time.current, notes: "Claimed by the voter")
      voter_race_baselines.recount!
      residence
    end
  end

  # Records somewhere this voter used to live, in the same shape as a current residence.
  def add_past_residence!(jurisdiction, started_on:, ended_on:, areas: {})
    residences.create!(jurisdiction: jurisdiction, **area_slots(areas), status: "moved",
      started_on: started_on, ended_on: ended_on, registered_at: Time.current, notes: "Added by the voter")
  end

  def area_slots(areas)
    Residence::AREA_SLOTS.to_h { |kind, slot| [ slot, areas[kind] ] }
  end

  # Whether any place this voter lives is where the race is decided, so their mountain counts with residents.
  def resident_of?(race)
    lives_in?(race.office.jurisdiction_id)
  end

  def lives_in?(jurisdiction)
    ballot_jurisdictions.where(id: jurisdiction).exists?
  end

  # Ends one current residence and re-sorts saved mountains for the places still lived in.
  def move_out_of!(residence)
    transaction do
      residence.move_out!
      voter_race_baselines.recount!
    end
  end

  def ballot
    Ballot.new(self)
  end

  # How far this voter has got on each of the given races, as { race_id => "saved" | "started" };
  # untouched races are left out. A saved race with an unsaved draft counts as started.
  def mountain_progress(races)
    drafted = mountain_drafts.where(race: races).pluck(:race_id)
    rated = ratings.joins(:candidacy).where(candidacies: { race_id: races.select(:id) }).distinct.pluck("candidacies.race_id")
    saved = voter_race_baselines.where(race: races).pluck(:race_id) - drafted
    (rated + drafted).index_with("started").merge(saved.index_with("saved"))
  end

  def residence_history
    residences.chronological
  end
end
