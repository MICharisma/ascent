# A timed import of a sample of real citizens into Rizz (rake
# rizz:import_sample[LIMIT]), for testing the ingest before a full sync.
#
# Only citizens whose name columns take a shape Rizz can read with confidence
# (Rizz::Ascent::NameShape) are sampled; every other real citizen goes to an
# overflow CSV with the reason, for triage. The sample order is fixed by the
# seed, so a larger sample contains every smaller one and re-runs skip the
# citizens already synced. The same_names mode samples instead the citizens
# who share their full name with another accepted citizen, grouped by name,
# to exercise Rizz's identity reviews; the jev mode samples citizens whose
# names only Jev's reading lets Rizz read (rake rizz:read_overflow first). Each Rizz call is timed, and the report goes to
# stdout and to a JSON file in tmp/.
class RizzImportSample
  # Times every Rizz client call, by method name.
  class TimedClient < SimpleDelegator
    attr_reader :timings

    def initialize(client)
      super
      @timings = Hash.new { |hash, key| hash[key] = [] }
    end

    %i[import_person display_names events entity].each do |method|
      define_method(method) do |*args, **options, &block|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        __getobj__.public_send(method, *args, **options, &block)
      ensure
        @timings[method] << Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      end
    end
  end

  MODES = %w[random same_names jev].freeze

  def initialize(limit:, mode: "random", seed: "rizz-import-sample", client: RizzCitizenSync.client, output: Rails.root.join("tmp"))
    raise ArgumentError, "mode must be one of #{MODES.join(', ')}" unless MODES.include?(mode)
    @limit = limit
    @mode = mode
    @seed = seed
    @client = TimedClient.new(client)
    @output = output
  end

  def call
    shapes = classify
    selected = sample(shapes)
    syncs = import(selected)
    report = report(shapes, selected, syncs)
    path = @output.join("rizz_import_sample-#{@mode}-#{@limit}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.json")
    File.write(path, JSON.pretty_generate(report))
    puts JSON.pretty_generate(report.except(:reviews, :failures))
    puts "Report: #{path}"
    puts "Overflow: #{overflow_path}"
    report
  end

  private

  def classify
    rows = Citizen.real.order(:id).pluck(:id, :first_name, :middle_name, :last_name)
    shapes = rows.to_h { |id, first, middle, last| [ id, Rizz::Ascent::NameShape.classify(first, middle, last) ] }
    @names = rows.to_h { |id, first, middle, last| [ id, [ first, middle, last ].compact_blank.join(" ") ] }
    CSV.open(overflow_path, "w") do |csv|
      csv << %w[citizen_id reason full_name first_name middle_name last_name]
      rows.each do |id, first, middle, last|
        next if Rizz::Ascent::NameShape.accepted?(shapes[id])
        csv << [ id, shapes[id], [ first, middle, last ].compact_blank.join(" "), first, middle, last ]
      end
    end
    shapes
  end

  def overflow_path
    @output.join("rizz_name_overflow.csv")
  end

  def sample(shapes)
    accepted = shapes.select { |_, shape| Rizz::Ascent::NameShape.accepted?(shape) }.keys
    return in_seed_order(accepted) if @mode == "random"
    return in_seed_order(CitizenNameReading.where(outcome: "jev", citizen_id: shapes.keys).pluck(:citizen_id)) if @mode == "jev"

    accepted.group_by { @names[it].downcase }.select { |_, ids| ids.size > 1 }.sort.flat_map { |_, ids| ids.sort }.first(@limit)
  end

  def in_seed_order(ids)
    ids.sort_by { Digest::SHA256.hexdigest("#{@seed}-#{it}") }.first(@limit)
  end

  def import(ids)
    sync = RizzCitizenSync.new(client: @client)
    citizens = RizzCitizenSync.citizens.where(id: ids).index_by(&:id)
    started = clock
    results = ids.map do |id|
      before = citizens[id].rizz_sync&.updated_at
      calls = @client.timings[:import_person].size
      record = sync.call(citizens[id])
      { citizen: citizens[id], sync: record, called: @client.timings[:import_person].size > calls, changed: record.updated_at != before }
    end
    @import_seconds = clock - started
    placed = results.select { it[:sync].state == "synced" && it[:called] }.map { it[:citizen] }
    started = clock
    names = RizzNames.new(client: @client)
    placed.each_slice(Rizz::Client::DISPLAY_BATCH_LIMIT) { names.refresh it }
    @refresh_seconds = clock - started
    results
  end

  def report(shapes, selected, results)
    imports = @client.timings[:import_person]
    {
      limit: @limit, mode: @mode, seed: @seed, endpoint: ENV["RIZZ_ENDPOINT"],
      real_citizens: shapes.size,
      shapes: shapes.values.tally.sort_by { -it.last }.to_h,
      accepted: shapes.values.count { Rizz::Ascent::NameShape.accepted?(it) },
      sampled: selected.size,
      states: results.map { it[:sync].state }.tally,
      distinct_names: selected.map { @names[it].downcase }.uniq.size,
      import_calls: imports.size,
      skipped_unchanged: results.count { !it[:called] && it[:sync].state == "synced" },
      import_seconds: @import_seconds.round(3),
      imports_per_second: imports.any? ? (imports.size / @import_seconds).round(2) : nil,
      import_call_ms: stats(imports),
      conflict_refetches: @client.timings[:entity].size,
      display_batches: @client.timings[:display_names].size,
      display_batch_ms: stats(@client.timings[:display_names]),
      refresh_seconds: @refresh_seconds.round(3),
      reviews: results.select { it[:sync].state == "review" }.map { { citizen_id: it[:citizen].id, name: it[:citizen].full_name, review_id: it[:sync].review_id } },
      failures: results.select { %w[failed skipped merge_needed].include?(it[:sync].state) }
        .map { { citizen_id: it[:citizen].id, name: it[:citizen].full_name, state: it[:sync].state, error: it[:sync].last_error } }
    }
  end

  def stats(seconds)
    return nil if seconds.empty?
    sorted = seconds.sort
    at = ->(fraction) { (sorted[((sorted.size - 1) * fraction).round] * 1000).round(1) }
    { count: sorted.size, p50: at.(0.5), p95: at.(0.95), max: at.(1.0), mean: (sorted.sum / sorted.size * 1000).round(1) }
  end

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
