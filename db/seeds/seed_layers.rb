module SeedLayers
  REFERENCE_SEEDER_FILES = %w[
    country_seeder
    state_seeder
    municipality_seeder
    year_seeder
    seed_manifests
    gubernatorial_race_seeder
  ].freeze

  SIMULATED_SEEDER_FILES = %w[
    governance_type_seeder
    area_of_concern_seeder
    governing_body_seeder
    policy_seeder
    official_code_seeder
    office_seeder
    election_seeder
    citizen_seeder
    candidacy_seeder
    stance_seeder
    voter_seeder
    residence_seeder
    rating_seeder
    voter_race_baseline_seeder
  ].freeze

  module_function

  def seed_reference!
    load_seeders!

    puts "🌱 Seeding reference data..."
    CountrySeeder.seed(SeedDataPaths.file("countries.yml"))
    StateSeeder.seed([
      SeedDataPaths.file("us_states.yml"),
      SeedDataPaths.file("canadian_provinces.yml")
    ])
    YearSeeder.seed
    # Manifests first, so places they define arrive with their counties before cities.yml adopts them.
    SeedManifests.seed
    MunicipalitySeeder.seed
    GubernatorialRaceSeeder.seed
    activated_races = Race.upcoming.update_all(status: "active", updated_at: Time.current)
    puts "Activated #{activated_races} upcoming races"
    puts "✅ Reference data seeded"
  end

  def seed_simulated!
    seed_reference!

    puts "\n🎭 Seeding simulated data..."
    GovernanceTypeSeeder.seed
    AreaOfConcernSeeder.seed
    GoverningBodySeeder.seed
    PolicySeeder.seed
    OfficialCodeSeeder.seed
    OfficeSeeder.seed
    ElectionSeeder.seed
    CitizenSeeder.seed
    CandidacySeeder.seed
    StanceSeeder.seed
    VoterSeeder.seed
    ResidenceSeeder.seed
    RatingSeeder.seed
    VoterRaceBaselineSeeder.seed
    puts "✅ Simulated data seeded"
  end

  def load_seeders!
    return if defined?(@seeders_loaded) && @seeders_loaded

    require Rails.root.join("db", "seeds", "data_paths")
    require Rails.root.join("db", "seeds", "simulated_data_paths")
    require Rails.root.join("db", "seeds", "seed_jurisdictions")

    (REFERENCE_SEEDER_FILES + SIMULATED_SEEDER_FILES).each do |seeder_file|
      require Rails.root.join("db", "seeds", seeder_file)
    end

    @seeders_loaded = true
  end
  private_class_method :load_seeders!
end
