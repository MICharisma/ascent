require "rails_helper"
require "rake"
require "stringio"

RSpec.describe "Mountain development scenarios", type: :request do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("dev:mountains")
  end

  it "prints working Mountain links for all six scenarios on repeated runs" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
    output = StringIO.new
    original_stdout = $stdout
    begin
      $stdout = output
      2.times { Rake::Task["dev:mountains"].execute }
    ensure
      $stdout = original_stdout
    end
    links = output.string.scan(%r{/mountains/\d+\?voter_id=\d+})

    expect(links.uniq.size).to eq(12)
    sign_in create(:voter, :admin)
    links.each do |link|
      get link
      expect(response).to have_http_status(:ok)
    end
  end

  it "refuses to create scenarios outside development" do
    expect(FactoryBot).not_to receive(:create)
    expect { Rake::Task["dev:mountains"].execute }
      .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      .and output("dev:mountains is development-only\n").to_stderr
  end
end
