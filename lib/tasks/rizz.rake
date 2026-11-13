namespace :rizz do
  desc "Preview confirmed Citizen consolidations as JSON; APPLY=/path/to/plan.json applies that exact plan (PERFORMED_BY required)"
  task consolidate_citizens: :environment do
    if ENV["APPLY"].present?
      result = CitizenConsolidation.apply(JSON.parse(File.read(ENV.fetch("APPLY"))), performed_by: ENV.fetch("PERFORMED_BY"))
      puts JSON.pretty_generate(result)
    else
      puts JSON.pretty_generate(CitizenConsolidation.preview)
    end
  end

  desc "Send real citizens to Rizz, adopt the codes it assigns, and fetch their names (needs rizz-client, RIZZ_ENDPOINT, RIZZ_API_TOKEN, RIZZ_SCOPE)"
  task sync_citizens: :environment do
    sync = RizzCitizenSync.new
    counts = Hash.new(0)
    placed = []
    RizzCitizenSync.citizens.find_each do |citizen|
      state = sync.call(citizen).state
      counts[state] += 1
      placed << citizen if state == "synced"
    end
    puts RizzSync::STATES.filter_map { |state| "#{state}: #{counts[state]}" if counts[state].positive? }.join(", ").presence || "No real citizens."
    # Newly placed citizens show their Rizz names now rather than after the daily revalidation.
    names = RizzNames.new
    placed.each_slice(Rizz::Client::DISPLAY_BATCH_LIMIT) { names.refresh it }
  end

  desc "Import a timed sample (mode random, same_names or jev) of real citizens whose names Rizz can read, listing the rest in tmp/rizz_name_overflow.csv (needs rizz-client, RIZZ_ENDPOINT, RIZZ_API_TOKEN, RIZZ_SCOPE)"
  task :import_sample, [ :limit, :mode ] => :environment do |_, args|
    RizzImportSample.new(limit: Integer(args.fetch(:limit, 100)), mode: args.fetch(:mode, "random")).call
  end

  desc "Ask Jev to read the parts of each name the name-shape switch doesn't accept and store them for the sync, listing every reading in tmp/rizz_name_readings.csv (needs rizz-client, TYPESAFE_API_KEY)"
  task read_overflow: :environment do
    RizzOverflowReading.new.call
  end

  desc "Send names Jev couldn't read to Rizz's reviewers and take up their decisions (needs rizz-client, RIZZ_ENDPOINT, RIZZ_API_TOKEN)"
  task review_names: :environment do
    puts RizzNameReview.new.call.map { |outcome, count| "#{outcome}: #{count}" }.join(", ").presence || "No names waiting for review."
  end

  desc "Fetch the names Rizz authorizes for every real citizen into rizz_names (needs RIZZ_ENDPOINT, RIZZ_API_TOKEN, RIZZ_SCOPE)"
  task refresh_names: :environment do
    puts RizzNames.new.revalidate.map { |purpose, result| "#{purpose}: #{result}" }.join(", ")
  end

  desc "Apply Rizz name changes from its event feed to rizz_names"
  task poll_names: :environment do
    puts RizzNames.new.poll.map { |purpose, result| "#{purpose}: #{result}" }.join(", ")
  end
end
