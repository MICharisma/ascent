# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContent do
  describe ".load" do
    it "loads the approval voting page copy" do
      page = described_class.load("approval_voting")

      expect(page.fetch(:hero)).to include(:kicker, :title, :lead, :actions)
      expect(page.fetch(:sections)).to all(include(:type))
      expect(page.dig(:hero, :actions)).to all(include(:text, :path, :style))
    end

    it "loads the seed data FAQ copy" do
      page = described_class.load("faq")

      expect(page.fetch(:hero)).to include(:kicker, :title, :lead, :actions)
      expect(page.fetch(:sections)).to all(include(:type))
      expect(page.dig(:hero, :actions).first).to include(:text, :url, :style)
      expect(page.fetch(:sections).find { it[:type] == "code" }).to include(
        language: "yaml",
        filename: "playgrounds_once_per_decade.yml"
      )
    end

    it "loads the supporters page copy" do
      page = described_class.load("supporters")

      expect(page.fetch(:hero)).to include(:kicker, :title, :lead, :actions)
      expect(page.fetch(:funding).fetch(:items)).to all(include(:title, :copy))
      expect(page.fetch(:values).fetch(:items)).to all(include(:title, :copy))
      expect(page.fetch(:support_targets).fetch(:items)).to all(include(:title, :copy))
      expect(page.fetch(:footprint)).to include(:title, :copy, :mountain_link, :empty)
      expect(page.dig(:footprint, :copy)).to include("%{active_elections}", "%{offices}", "%{topics}", "%{issues}")
    end

    it "loads the glossary page copy" do
      page = described_class.load("glossary")

      expect(page.fetch(:hero)).to include(:kicker, :title, :lead, :actions)
      expect(page.fetch(:flow).fetch(:items)).to all(include(:title, :chain, :copy))
      expect(page.fetch(:sections)).to all(include(:kicker, :title, :entries))
      expect(page.fetch(:sections).flat_map { it.fetch(:entries) }).to all(include(:term, :definition))
    end

    it "loads the error page copy" do
      page = described_class.load("errors")

      expect(page.fetch(:not_found)).to include(:code, :kicker, :title, :lead, :actions)
      expect(page.fetch(:internal_server_error)).to include(:code, :kicker, :title, :lead, :actions)
      expect(page.dig(:not_found, :code)).to eq("404")
      expect(page.dig(:internal_server_error, :code)).to eq("500")
    end
  end
end
