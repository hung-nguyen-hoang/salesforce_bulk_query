require 'spec_helper'
require 'multi_json'

describe SalesforceBulkQuery do

  before :each do
    auth = MultiJson.load(File.read('test_salesforce_credentials.json'), :symbolize_keys => true)

    @client = Restforce.new(
      :username => auth[:username]
      :password => auth[:password],
      :security_token => auth[:token],
      :client_id => auth[:client_id],
      :client_secret => auth[:client_secret]
    )
    @api = SalesforceBulkApi::Api.new(@client)
  end
end