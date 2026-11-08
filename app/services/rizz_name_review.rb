# Sends the names Jev couldn't read with confidence to Rizz's reviewers and
# takes up their decisions (rake rizz:review_names). Each overflow reading
# goes to Rizz with the readings code proposed and Jev's pick; a reviewer
# settles it with one of them on Rizz's review page, or rejects them all.
# A decision on the name as it is still spelled becomes the reading's
# outcome, and the next sync sends a settled name with its chosen parts.
# Needs rizz-client, RIZZ_ENDPOINT and RIZZ_API_TOKEN.
class RizzNameReview
  BATCH = 100

  def initialize(client: RizzCitizenSync.client)
    @client = client
  end

  # { queued:, settled:, rejected:, waiting: }
  def call
    counts = Hash.new(0)
    readings.each_slice(BATCH) do |batch|
      batch.each do |reading|
        submit(reading)
        counts[:queued] += 1
      end
      decisions = @client.name_readings(batch.map { it.citizen_id.to_s }).index_by { it.fetch("person_external_id") }
      batch.each { counts[apply(it, decisions[it.citizen_id.to_s])] += 1 }
    end
    counts.slice(:queued, :settled, :rejected, :waiting)
  end

  private

  def readings
    CitizenNameReading.where(outcome: "overflow").includes(:citizen).order(:citizen_id).select(&:current?)
  end

  def submit(reading)
    citizen = reading.citizen
    candidates = Rizz::Ascent::NameReader.candidates(citizen.first_name, citizen.middle_name, citizen.last_name)
    pick = candidates.index { Rizz::Ascent::NameReader.describe(it) == reading.pick }
    @client.submit_name_reading(person_external_id: citizen.id.to_s, name_text: reading.name_text, candidates: candidates,
      reason: reading.shape, recorded_as: { first_name: citizen.first_name, middle_name: citizen.middle_name, last_name: citizen.last_name },
      assessment: { model: reading.model, pick: pick, probability: reading.probability }.compact)
  end

  def apply(reading, decision)
    return :waiting unless decision && decision["name_text"] == reading.name_text

    case decision["status"]
    when "settled"
      parts = decision.fetch("parts")
      reading.update!(outcome: "settled", parts: parts, pick: Rizz::Ascent::NameReader.describe(parts), reviewed_by: decision["decided_by"])
      :settled
    when "rejected"
      reading.update!(outcome: "rejected", parts: nil, pick: "none", reviewed_by: decision["decided_by"])
      :rejected
    else
      :waiting
    end
  end
end
