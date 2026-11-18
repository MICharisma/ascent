# Sends the names Jev couldn't read with confidence to Rizz's reviewers and
# takes up their decisions (rake rizz:review_names). Each overflow reading
# goes to Rizz with the readings code proposed and Jev's pick; a reviewer
# settles it with one of them on Rizz's review page, or rejects them all.
# A decision on the name as it is still spelled becomes the reading's
# outcome, and the next sync sends a settled name with its chosen parts.
# A queued name Jev has since read with confidence is withdrawn from the
# queue, unless a reviewer already decided it: the reviewer's decision wins.
# Needs rizz-client, RIZZ_ENDPOINT and RIZZ_API_TOKEN.
class RizzNameReview
  BATCH = 100

  def initialize(client: RizzCitizenSync.client)
    @client = client
  end

  # { queued:, settled:, rejected:, waiting:, withdrawn: }
  def call
    counts = Hash.new(0)
    withdraw_read_names(counts)
    readings.each_slice(BATCH) do |batch|
      batch.each do |reading|
        submit(reading)
        counts[:queued] += 1
      end
      decisions = @client.name_readings(batch.map { it.citizen_id.to_s }).index_by { it.fetch("person_external_id") }
      batch.each { counts[apply(it, decisions[it.citizen_id.to_s])] += 1 }
    end
    counts.slice(:queued, :settled, :rejected, :waiting, :withdrawn)
  end

  private

  def withdraw_read_names(counts)
    CitizenNameReading.where(outcome: "jev").where.not(queued_at: nil).find_each do |reading|
      result = begin
        @client.withdraw_name_reading(person_external_id: reading.citizen_id.to_s, name_text: reading.name_text)
      rescue Rizz::Error => error
        raise unless error.status == 404
        {}
      end
      outcome = apply(reading, result)
      counts[outcome == :waiting ? :withdrawn : outcome] += 1
      reading.update!(queued_at: nil) if outcome == :waiting
    end
  end

  def readings
    CitizenNameReading.where(outcome: "overflow").includes(:citizen).order(:citizen_id).select(&:current?)
  end

  def submit(reading)
    citizen = reading.citizen
    candidates = Rizz::Ascent::NameReader.candidates(citizen.first_name, citizen.middle_name, citizen.last_name)
    pick = candidates.index { Rizz::Ascent::NameReader.describe(it) == reading.pick }
    reading.update!(queued_at: Time.current)
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
