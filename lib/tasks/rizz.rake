namespace :rizz do
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

  desc "Fetch the names Rizz authorizes for every real citizen into rizz_names (needs RIZZ_ENDPOINT, RIZZ_API_TOKEN, RIZZ_SCOPE)"
  task refresh_names: :environment do
    puts RizzNames.new.revalidate.map { |purpose, result| "#{purpose}: #{result}" }.join(", ")
  end

  desc "Apply Rizz name changes from its event feed to rizz_names"
  task poll_names: :environment do
    puts RizzNames.new.poll.map { |purpose, result| "#{purpose}: #{result}" }.join(", ")
  end
end
