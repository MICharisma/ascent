namespace :dev do
  desc "Create named Mountain product scenarios in development"
  task mountains: :environment do
    abort "dev:mountains is development-only" unless Rails.env.development?

    FactoryBot.reload

    scenarios = {
      "default" => :mountain_scenario,
      "crowded-primary" => :crowded_primary_mountain,
      "knife-edge" => :knife_edge_mountain,
      "enthusiastic" => :enthusiastic_mountain,
      "selective" => :selective_mountain,
      "polarized" => :polarized_mountain
    }

    puts "Creating Mountain development scenarios..."

    scenarios.each do |name, factory|
      scenario = FactoryBot.create(factory)
      race = scenario.fetch(:race)
      voter = scenario.fetch(:voter)
      baseline = scenario.fetch(:baseline)

      puts format(
        "  %-16s race=%-4s voter=%-4s baseline=%-3s  /mountains/%s?voter_id=%s",
        name,
        race.id,
        voter.id,
        baseline.baseline,
        race.id,
        voter.id
      )
    end

    puts "Done. Open any URL above to compare the shapes."
  end
end
