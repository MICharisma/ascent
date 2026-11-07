namespace :rizz do
  desc "Adopt Rizz place codes for countries, states, counties and incorporated places, keeping Ascent's codes as aliases " \
       "(needs rizz-client, RIZZ_ENDPOINT, RIZZ_API_TOKEN; municipalities need imported TIGER place GEOIDs)"
  task sync_places: :environment do
    outcomes = RizzPlaceSync.new.call
    outcomes.group_by { it.record.class.name }.each do |model, group|
      puts "#{model}: #{group.group_by(&:state).map { |state, items| "#{state} #{items.size}" }.join(", ")}"
    end
    problems = outcomes.reject { %w[adopted unchanged].include?(it.state) || it.detail == "not an incorporated Census place" }
    problems.first(50).each { puts "  #{it.state} #{it.record.class.name} #{it.record.id} #{it.record.entity_code}: #{it.detail}" }
    puts "  ...and #{problems.size - 50} more" if problems.size > 50
  end
end
