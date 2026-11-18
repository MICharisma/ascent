require "rails_helper"

RSpec.describe PortraitGenerator do
  let(:citizen) { create(:citizen, first_name: "Avery", middle_name: nil, last_name: "Example") }
  let(:reference) { create(:image, :uploaded).tap { citizen.images << it } }
  let(:configuration) { Rails.application.config.x.portrait_generation }

  it "remains disabled before reading the reference file or contacting OpenAI" do
    expect(configuration.enabled).to be(false)
    generator = described_class.new(subject: citizen, reference_image: reference, style: "pen_ink")
    expect(reference.file).not_to receive(:download)
    expect(Net::HTTP).not_to receive(:start)
    expect { generator.call }.to raise_error(described_class::Disabled, /legal review/)
  end

  context "with generation enabled only in isolated tests" do
    before do
      allow(configuration).to receive(:enabled).and_return(true)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-key")
    end

    def response(status: "200", body:)
      result = Net::HTTPResponse::CODE_TO_OBJ.fetch(status).new("1.1", status, "Test response")
      result.body = body
      result.instance_variable_set(:@read, true)
      result
    end

    it "builds each style, stores generated provenance, and attaches results to the subject" do
      file = File.binread(Rails.root.join("spec/fixtures/files/portrait.png"))
      http = instance_double(Net::HTTP)
      requests = []
      allow(Net::HTTP).to receive(:start).with("api.openai.com", 443, use_ssl: true, open_timeout: 10, read_timeout: 180).and_yield(http)
      allow(http).to receive(:request) do |request|
        requests << JSON.parse(request.body)
        expect(request["Authorization"]).to eq("Bearer test-key")
        response(body: JSON.generate(data: [ { b64_json: Base64.strict_encode64(file) } ]))
      end
      described_class::STYLES.each_key do |style|
        image = described_class.new(subject: citizen, reference_image: reference, style: style, random: Random.new(42)).call
        expect(image).to be_ai_generated
        expect(image.file.download).to eq(file)
        expect(image.citizens).to include(citizen)
        provenance = image.file.blob.metadata.fetch("portrait_generation")
        expect(provenance).to include("style" => style, "model" => configuration.model, "reference_image_id" => reference.id,
          "reference_blob_id" => reference.file.blob.id)
        expect(provenance.fetch("prompt")).to include("Avery Example", "imagined illustration")
        if style == "american_pastime"
          expect(described_class::PASTIMES).to include(provenance.fetch("pastime"))
          expect(provenance.fetch("prompt")).to include(provenance.fetch("pastime"))
        end
      end
      expect(requests.size).to eq(4)
      expect(requests).to all(include("model" => configuration.model, "size" => "1024x1536", "output_format" => "png", "n" => 1))
      expect(requests.first.fetch("images").first.fetch("image_url")).to start_with("data:image/png;base64,")
    end

    it "rejects invalid styles or reference images from another profile before calling OpenAI" do
      other = create(:citizen)
      expect(Net::HTTP).not_to receive(:start)
      expect { described_class.new(subject: other, reference_image: reference, style: "pen_ink").call }
        .to raise_error(ArgumentError, /this profile/)
      expect { described_class.new(subject: citizen, reference_image: reference, style: "unknown").call }
        .to raise_error(ArgumentError, /Unknown portrait style/)
    end

    it "does not create an image when the provider fails or returns invalid output" do
      reference
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      [ response(status: "429", body: "rate limited"), response(body: '{"data":[]}'),
        response(body: JSON.generate(data: [ { b64_json: "not base64!" } ])) ].each do |result|
        allow(http).to receive(:request).and_return(result)
        expect do
          expect { described_class.new(subject: citizen, reference_image: reference, style: "pen_ink").call }.to raise_error(described_class::Error)
        end.not_to change(Image, :count)
      end
    end
  end
end
