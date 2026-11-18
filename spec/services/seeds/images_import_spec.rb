require "rails_helper"

RSpec.describe "Importing shared profile images" do
  let(:example) { Rails.root.join("db/seeds/ascent_seed_data/examples/profile_images.yml") }
  let!(:citizen) { create(:citizen, entity_code: "CITIZEN-EXAMPLE_AV_7K") }
  let!(:other) { create(:citizen, entity_code: "CITIZEN-SAMPLE_JN_8P") }
  let!(:candidacy) { create(:candidacy, citizen: citizen, entity_code: "CANDIDACY-USA-NY-GOVERNOR-2026_GENERAL-EXAMPLE_AV_7K") }

  it "imports a reusable image for multiple existing subjects, with ordered placements and repeatable JSON and YAML" do
    importer = Seeds::LibraryImporter.new
    importer.call([ example.to_s ])
    shared = Image.find_by!(entity_code: "IMAGE-EXAMPLE-COMMUNITY_MEETING")
    portrait = Image.find_by!(entity_code: "IMAGE-EXAMPLE-AVERY_PORTRAIT")
    expect(citizen.images).to eq([ portrait, shared ])
    expect(other.images).to eq([ shared ])
    expect(candidacy.images).to eq([ shared ])
    expect(shared.citizens).to contain_exactly(citizen, other)
    expect(ImagePlacement.count).to eq(4)
    expect(importer.report[:conflicts]).to be_empty

    Dir.mktmpdir("image-seeds") do |directory|
      path = File.join(directory, "images.json")
      File.write(path, JSON.generate(YAML.safe_load(example.read)))
      counts = -> { [ Image.count, ImagePlacement.count, Citizen.count, Candidacy.count, EntityCode.count ] }
      expect { importer.call([ example.to_s, path ]) }.not_to change(&counts)
      expect(importer.report[:conflicts]).to be_empty
    end
  end

  it "rejects a second code for one image URL and an unsupported placement subject" do
    Seeds::LibraryImporter.new.call([ example.to_s ])
    document = YAML.safe_load(example.read)
    document.fetch("records").first["code"] = "IMAGE-EXAMPLE-SECOND_CODE"
    Dir.mktmpdir("invalid-image-seeds") do |directory|
      path = File.join(directory, "images.json")
      File.write(path, JSON.generate(document))
      expect { Seeds::LibraryImporter.new.call([ path ]) }.to raise_error(Seeds::LibraryImporter::Error, /same Image/)

      document = YAML.safe_load(example.read)
      document.fetch("records")[2]["references"]["subject"] = "RACE-USA-NY-GOVERNOR-2026_GENERAL"
      File.write(path, JSON.generate(document))
      expect { Seeds::LibraryImporter.new.call([ path ]) }.to raise_error(Seeds::LibraryImporter::Error, /not a Citizen, Candidacy code/)
    end
  end
end
