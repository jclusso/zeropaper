ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "webmock/minitest"
require "httpx/adapters/webmock"
require "vcr"
require_relative "test_helpers/session_test_helper"
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

WebMock.disable_net_connect!(allow_localhost: true)

VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("vcr_cassettes", __dir__)
  config.hook_into :webmock
  config.ignore_localhost = true
  config.default_cassette_options = { record: :none, match_requests_on: %i[method uri] }
  config.filter_sensitive_data("<OPENAI_API_KEY>") { TestKeys::OPENAI }
  config.filter_sensitive_data("<MISTRAL_API_KEY>") { TestKeys::MISTRAL }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { TestKeys::ANTHROPIC }
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup { ActionController::Base.cache_store.clear }

    include ActiveJob::TestHelper
    include PdfFactory::Helpers
    include DocumentHelpers
  end
end
