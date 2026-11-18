require "rails_helper"

RSpec.describe "Importing communications and stance evidence" do
  let(:town_hall) { Rails.root.join("spec/fixtures/seed_library/communications/a_town_hall.yml").to_s }
  let(:debate_clip) { Rails.root.join("spec/fixtures/seed_library/communications/b_debate_clip.yml").to_s }
  let(:stance_code) { "STANCE-USA-NY-EXAMPLE-ED_1-2026_GENERAL-EXAMPLE_AV_7K-ENVIRONMENT-ENERGY_INTENSIVE_MINING-TIME_LIMITED_PERMIT_MORATORIUM" }

  before { Year.create!(year: 2026, is_even_year: true, is_presidential_year: false) }

  it "lets a second contribution add evidence to an existing stance" do
    Seeds::LibraryImporter.new.call([ town_hall ])
    report = Seeds::LibraryImporter.new.call([ debate_clip ])

    expect(report[:conflicts]).to be_empty
    stance = Stance.find_by!(entity_code: stance_code)
    expect(stance.stance_evidences.map { |evidence| [ evidence.relation, evidence.timestamp ] })
      .to contain_exactly([ "states", "1:42" ], [ "clarifies", "25:05" ])
    expect(stance.communications.map(&:kind)).to contain_exactly("video", "debate")

    channel = Channel.find_by!(entity_code: "CHANNEL-WEB-AVERYEXAMPLE_EXAMPLE_COM")
    expect(channel).to have_attributes(official: true, owner: Citizen.find_by!(username: "example_av_7k"))
    expect(stance.candidacy.featured_communications.count).to eq(2)
  end

  it "imports both contributions together and re-imports without change" do
    importer = Seeds::LibraryImporter.new
    importer.call([ town_hall, debate_clip ])
    counts = -> { [ Channel, Communication, CommunicationFeature, Stance, StanceEvidence, EntityCode ].map(&:count) }

    expect { importer.call([ town_hall, debate_clip ]) }.not_to change(&counts)
    expect(importer.report[:conflicts]).to be_empty
    expect(importer.report[:features_added]).to be_empty
  end

  it "attaches worker account submissions in JSON and YAML to existing citizens and candidacies" do
    importer = Seeds::LibraryImporter.new
    importer.call([ town_hall ])
    citizen = Citizen.find_by!(username: "example_av_7k")
    candidacy = citizen.candidacies.sole
    template = Rails.root.join("db/seeds/ascent_seed_data/examples/candidate_accounts.json")
    document = JSON.parse(template.read)
    document.fetch("records").zip([ citizen, candidacy ]).each do |record, owner|
      record.fetch("references")["owner"] = owner.entity_code
    end

    Dir.mktmpdir("candidate-accounts") do |directory|
      paths = %w[json yml].map do |extension|
        path = File.join(directory, "accounts.#{extension}")
        File.write(path, extension == "json" ? JSON.generate(document) : YAML.dump(document))
        path
      end
      expect { importer.call([ paths.first ]) }.to change(Channel, :count).by(2)
      document.fetch("records").zip([ citizen, candidacy ]).each do |record, owner|
        channel = Channel.find_by!(entity_code: record.fetch("code"))
        expect(channel).to have_attributes(owner: owner, official: true, url: record.dig("attributes", "url"))
      end
      expect { importer.call(paths) }.not_to change(Channel, :count)
      expect(importer.report[:conflicts]).to be_empty
      expect(Citizen.count).to eq(1)
      expect(Candidacy.count).to eq(1)
    end
  end

  # A platform and handle name one account, so a second code for it has to be declared as an alias.
  it "refuses a second code for the same account" do
    Seeds::LibraryImporter.new.call([ town_hall ])
    path = Rails.root.join("tmp", "communications_import_spec", "second_code.yml")
    FileUtils.mkdir_p(path.dirname)
    path.write(<<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      records:
        - type: Channel
          code: CHANNEL-WEB-AVERY_FOR_ASSEMBLY
          attributes: {platform: website, handle: averyexample.example.com, official: true}
    YAML

    expect { Seeds::LibraryImporter.new.call([ path.to_s ]) }
      .to raise_error(Seeds::LibraryImporter::Error, /names the same Channel as CHANNEL-WEB-AVERYEXAMPLE_EXAMPLE_COM; use that code or list CHANNEL-WEB-AVERY_FOR_ASSEMBLY in its aliases/)
    expect(Channel.count).to eq(1)
  end

  it "rejects a channel owner that is not a citizen, organization, or candidacy" do
    path = Rails.root.join("tmp", "communications_import_spec", "bad_owner.yml")
    FileUtils.mkdir_p(path.dirname)
    path.write(File.read(town_hall).sub("references: {owner: CITIZEN-EXAMPLE_AV_7K}", "references: {owner: STATE-USA-NY}"))

    expect { Seeds::LibraryImporter.new.call([ path.to_s ]) }.to raise_error(Seeds::LibraryImporter::Error, /not a Citizen, Organization, Candidacy, Party code/)
  end
end
