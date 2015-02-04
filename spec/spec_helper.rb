require 'salesforce_bulk_query'
require 'restforce'
require 'webmock/rspec'

RSpec.configure do |c|
  c.filter_run :focus => true
  c.run_all_when_everything_filtered = true
  c.filter_run_excluding :skip => true
  c.formatter = :documentation
end

class SpecHelper
  DEFAULT_API_VERSION = '30.0'
  def self.create_default_restforce
    Restforce.new(
      :username => ENV['USERNAME'],
      :password => ENV['PASSWORD'],
      :security_token => ENV['TOKEN'],
      :client_id => ENV['CLIENT_ID'],
      :client_secret => ENV['CLIENT_SECRET'],
      :api_version => api_version
    )
  end

  def self.api_version
    ENV['API_VERSION'] || DEFAULT_API_VERSION
  end

  def self.create_default_api(restforce)
    # switch off the normal logging
    Restforce.log = false

    SalesforceBulkQuery::Api.new(restforce,
      :api_version => ENV['API_VERSION'] || DEFAULT_API_VERSION,
      :logger => ENV['LOGGING'] ? Logger.new(STDOUT): nil
    )
  end
end