class Citizen < ApplicationRecord
  include Engageable
  include Illustrated

  RIZZ_NAMESPACE = "MIC".freeze
  RIZZ_CATALOG = "RZZ".freeze
  RIZZ_PREFIX = "#{RIZZ_NAMESPACE}-#{RIZZ_CATALOG}-".freeze
  ASCENT_CATALOG = "ASC".freeze

  has_many :candidacies, dependent: :destroy
  has_one :rizz_sync, dependent: :delete
  has_many :rizz_names, dependent: :delete_all
  has_many :races, -> { distinct }, through: :candidacies
  has_many :elections, -> { distinct }, through: :races

  # Ballots name candidates without contact details, and some print only a surname.
  validates :last_name, presence: true
  validates :email, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  # Generated usernames stay provisional until a verified handle replaces them.
  validates :username, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }, allow_blank: true
  validates :username_status, inclusion: { in: %w[provisional verified] }, if: :username?

  # Invented candidates in mock elections are kept apart from real people.
  scope :real, -> { where(fictional: false) }
  scope :fictional, -> { where(fictional: true) }
  scope :with_candidacy_details, -> { includes(candidacies: { race: [ :election, { office: :position } ] }) }
  scope :with_recent_candidacies, -> {
    includes(candidacies: { race: [ :election, { office: :position } ] })
      .joins(candidacies: { race: :election })
      .order("elections.election_date DESC")
  }

  OWN_NAME_SQL = "concat_ws(' ', citizens.first_name, citizens.middle_name, citizens.last_name)".freeze
  REFERRING_ROW_SQL = "rizz_names.citizen_id = citizens.id AND rizz_names.purpose = 'referring'".freeze

  # With Rizz enabled, a citizen Rizz has answered for matches only the names
  # Rizz lets Ascent search (its display name and search forms), and one whose
  # name Rizz withholds matches nothing. Citizens Rizz hasn't been asked about
  # yet match their own name columns.
  RIZZ_SEARCH_SQL = <<~SQL.squish.freeze
    (NOT EXISTS (SELECT 1 FROM rizz_names WHERE #{REFERRING_ROW_SQL}) AND #{OWN_NAME_SQL} ILIKE :pattern)
    OR EXISTS (SELECT 1 FROM rizz_names WHERE #{REFERRING_ROW_SQL}
      AND rizz_names.state = 'current' AND rizz_names.display_name IS NOT NULL
      AND (rizz_names.display_name ILIKE :pattern
        OR EXISTS (SELECT 1 FROM jsonb_array_elements(rizz_names.search_forms) AS form WHERE form->>'exact_text' ILIKE :pattern)))
  SQL

  # The keys Citizen#sort_keys gives, in SQL.
  RIZZ_SORT_SQL = <<~SQL.squish.freeze
    COALESCE(
      (SELECT CASE WHEN rizz_names.state = 'current' AND rizz_names.display_name IS NOT NULL
        THEN COALESCE(rizz_names.name_sort, ARRAY[rizz_names.display_name::text, ''])
        ELSE ARRAY['#{RizzNames::NEUTRAL}', ''] END
       FROM rizz_names WHERE #{REFERRING_ROW_SQL}),
      ARRAY[citizens.last_name::text, concat_ws(' ', citizens.first_name, citizens.middle_name)])
  SQL

  scope :named_like, ->(query) {
    pattern = "%#{sanitize_sql_like(query.strip)}%"
    RizzNames.enabled? ? where(RIZZ_SEARCH_SQL, pattern: pattern) : where("#{OWN_NAME_SQL} ILIKE ?", pattern)
  }
  # Alphabetical by family name, then the other names: the names shown, so
  # the Rizz name's family name when Rizz is enabled.
  scope :by_name, -> {
    RizzNames.enabled? ? order(Arel.sql(RIZZ_SORT_SQL), :id) : order(:last_name, :first_name, :id)
  }
  scope :with_names, -> { includes(:rizz_names) }
  # Citizens with a candidacy in any of the races given.
  scope :ran_in, ->(races) { where(id: Candidacy.where(race: races).select(:citizen_id)) }

  def full_name
    [ first_name, middle_name, last_name ].compact.join(" ")
  end

  # The name pages show: the Rizz name when Rizz is enabled (display_name).
  # full_name stays the citizen's own name, as printed on ballots.
  def name
    display_name
  end

  # The name to show for this citizen. With Rizz enabled, that is the name Rizz
  # authorizes (rizz_names): a neutral label when Rizz has none Ascent may
  # show, and the citizen's own name until Rizz has been asked. The name
  # columns stay Ascent's source data and ballot spelling, and are never
  # overwritten from Rizz.
  def display_name(purpose: "referring")
    return full_name unless RizzNames.enabled?

    row = rizz_name(purpose)
    row ? row.label || RizzNames::NEUTRAL : full_name
  end

  # The family name in display_name, for mentions such as "Walker leads".
  # The whole display_name when the name has no family name, or Rizz doesn't
  # know which part it is.
  def display_family_name(purpose: "referring")
    parts = display_name_parts(purpose: purpose)
    (parts && NameParts.family(parts)) || display_name(purpose: purpose)
  end

  # What lists sort by: the family name, then the other names, of the name
  # shown. by_name sorts the same way in SQL.
  def sort_keys(purpose: "referring")
    row = rizz_name(purpose) if RizzNames.enabled?
    return [ last_name.to_s, [ first_name, middle_name ].compact_blank.join(" ") ] unless row
    return [ RizzNames::NEUTRAL, "" ] unless row.label
    row.name_sort || [ row.label, "" ]
  end

  # display_name in pieces, each a hash with its text and, for a name piece,
  # its role: given, middle, family, suffix, nickname or other. Nil when Rizz
  # doesn't know the name's structure, or shows the neutral label. Without
  # Rizz, or before Rizz has been asked, the pieces are the name columns.
  def display_name_parts(purpose: "referring")
    return own_name_parts unless RizzNames.enabled?

    row = rizz_name(purpose)
    row ? row.parts : own_name_parts
  end

  def own_name_parts
    [ [ first_name, "given" ], [ middle_name, "middle" ], [ last_name, "family" ] ].reject { |text, _| text.blank? }
      .flat_map { |text, role| [ { "text" => " " }, { "text" => text, "role" => role } ] }.drop(1)
  end

  def rizz_name(purpose)
    rizz_names.find { it.purpose == purpose }
  end

  def rizz_code?
    entity_code.to_s.start_with?(RIZZ_PREFIX)
  end

  # Makes a Rizz person code (MIC-RZZ-...) this citizen's canonical code. The
  # Ascent code it replaces (CITIZEN-...) and every earlier alias stay bound
  # to the citizen, so seed manifests, candidacy codes and links that use them
  # keep resolving. The username stays the citizen's handle.
  def adopt_rizz_code!(qualified_code)
    raise ArgumentError, "#{qualified_code.inspect} is not a Rizz person code" unless qualified_code.to_s.start_with?(RIZZ_PREFIX)
    return false if entity_code == qualified_code

    transaction do
      lock!
      previous = entity_code
      EntityCode.where(record_type: "Citizen", record_id: id).update_all(canonical_code: qualified_code, updated_at: Time.current)
      if previous.present?
        EntityCode.find_or_initialize_by(namespace: RIZZ_NAMESPACE, catalog: ASCENT_CATALOG, code: previous)
          .update!(canonical_code: qualified_code, record: self)
      end
      EntityCode.find_or_initialize_by(namespace: RIZZ_NAMESPACE, catalog: RIZZ_CATALOG, code: qualified_code.delete_prefix(RIZZ_PREFIX))
        .update!(canonical_code: qualified_code, record: self)
      update!(entity_code: qualified_code)
    end
    true
  end
end
