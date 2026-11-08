# Reads the parts of every real citizen's name that the name-shape switch
# doesn't accept (rake rizz:read_overflow) and stores each reading as the
# citizen's CitizenNameReading, which the Rizz sync sends as the name's parts.
# Jev is asked only about names without a current reading from the same
# model. Every overflow name's reading also goes to tmp/rizz_name_readings.csv
# for triage, with a summary by overflow reason on stdout and in tmp/.
# Needs rizz-client and TYPESAFE_API_KEY.
class RizzOverflowReading
  def initialize(threads: 8, threshold: Rizz::Ascent::NameReader::THRESHOLD, output: Rails.root.join("tmp"))
    require "rizz-client"
    @jev = Rizz::TypeSafe.from_env
    @reader = Rizz::Ascent::NameReader.new(jev: @jev, threshold: threshold)
    @threads = threads
    @threshold = threshold
    @output = output
  end

  def call
    rows = Citizen.real.order(:id).pluck(:id, :first_name, :middle_name, :last_name)
      .reject { |_, first, middle, last| Rizz::Ascent::NameShape.accepted?(Rizz::Ascent::NameShape.classify(first, middle, last)) }
    stored = CitizenNameReading.where(citizen_id: rows.map(&:first)).index_by(&:citizen_id)
    unread = rows.reject do |id, first, middle, last|
      stored[id] && stored[id].model == @jev.model && stored[id].name_text == Rizz::Ascent::NameReader.text(first, middle, last)
    end
    started = clock
    results = read(unread)
    seconds = clock - started
    save(results)
    readings = CitizenNameReading.where(citizen_id: rows.map(&:first)).index_by(&:citizen_id)
    write_csv(rows, readings)
    report = summary(rows, readings, results, seconds)
    File.write(@output.join("rizz_name_readings-#{Time.current.strftime('%Y%m%d-%H%M%S')}.json"), JSON.pretty_generate(report))
    puts JSON.pretty_generate(report)
    puts "Readings: #{csv_path}"
    report
  end

  private

  def read(rows)
    queue = Queue.new
    rows.each { queue << it }
    queue.close
    results = Queue.new
    Array.new(@threads) do
      Thread.new do
        while (row = queue.pop)
          started = clock
          reading = begin
            @reader.read(*row.drop(1))
          rescue Rizz::TypeSafe::Error => error
            error
          end
          results << [ row.first, reading, clock - started ]
        end
      end
    end.each(&:join)
    Array.new(results.size) { results.pop }
  end

  def save(results)
    now = Time.current
    rows = results.reject { it[1].is_a?(Exception) }.map do |id, reading, _|
      { citizen_id: id, name_text: reading.text, shape: reading.shape, outcome: reading.accepted? ? "jev" : "overflow",
        parts: reading.parts, probability: reading.probability, pick: reading.choice, model: @jev.model,
        candidates: reading.candidates.map { Rizz::Ascent::NameReader.describe(it) }, created_at: now, updated_at: now }
    end
    CitizenNameReading.upsert_all(rows, unique_by: :citizen_id) if rows.any?
  end

  def write_csv(rows, readings)
    CSV.open(csv_path, "w") do |csv|
      csv << %w[citizen_id reason outcome probability full_name jev_pick first_name middle_name last_name readings]
      rows.each do |id, first, middle, last|
        reading = readings[id]
        csv << [ id, reading&.shape, reading&.outcome || "unread", reading&.probability&.round(3), reading&.name_text,
                 reading&.pick, first, middle, last, reading&.candidates&.join(" / ") ]
      end
    end
  end

  def csv_path
    @output.join("rizz_name_readings.csv")
  end

  def summary(rows, readings, results, seconds)
    current = readings.values
    latencies = results.map(&:last).sort
    {
      threshold: @threshold, model: @jev.model, overflow_names: rows.size,
      read_now: results.size, errors: results.count { it[1].is_a?(Exception) },
      seconds: seconds.round(1), call_ms: (latencies.any? ? { p50: ms(latencies[latencies.size / 2]), p95: ms(latencies[(latencies.size * 0.95).floor]) } : nil),
      jev: current.count { it.outcome == "jev" }, overflow: current.count { it.outcome == "overflow" }, unread: rows.size - current.size,
      by_reason: current.group_by(&:shape).sort_by { -it.last.size }.to_h { |reason, list| [ reason, { names: list.size, jev: list.count { it.outcome == "jev" } } ] }
    }
  end

  def ms(seconds)
    (seconds * 1000).round
  end

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
