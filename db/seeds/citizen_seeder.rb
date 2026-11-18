class CitizenSeeder
  def self.seed
    citizens_data = YAML.load_file(SimulatedSeedDataPaths.file("citizens.yml"))

    citizens_data.each do |citizen_data|
      Citizen.find_or_create_by(email: citizen_data["email"]) do |citizen|
        citizen.first_name = citizen_data["first_name"]
        citizen.last_name = citizen_data["last_name"]
        citizen.middle_name = citizen_data["middle_name"]
        citizen.birth_date = Date.parse(citizen_data["birth_date"]) if citizen_data["birth_date"]
        citizen.bio = citizen_data["bio"]
      end
    end

    puts "Seeded #{Citizen.count} citizens"
  end
end
