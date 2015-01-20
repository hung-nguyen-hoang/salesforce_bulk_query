require 'spec_helper'
require 'multi_json'
require 'restforce'
require 'csv'
require 'tmpdir'
require 'logger'

LOGGING = false

describe SalesforceBulkQuery do

  before :all do
    auth = MultiJson.load(File.read('test_salesforce_credentials.json'), :symbolize_keys => true)

    @client = Restforce.new(
      :username => auth[:username],
      :password => auth[:password],
      :security_token => auth[:token],
      :client_id => auth[:client_id],
      :client_secret => auth[:client_secret],
      :api_version => '30.0'
    )
    @api = SalesforceBulkQuery::Api.new(@client,
      :api_version => '30.0',
      :logger => LOGGING ? Logger.new(STDOUT): nil
    )

    # switch off the normal logging
    Restforce.log = false
  end

  describe "instance_url" do
    it "gives you some reasonable url" do
      url = @api.instance_url
      url.should_not be_empty
      url.should match(/salesforce\.com\//)
    end
  end

  describe "query" do
    context "when you give it no options" do
      it "downloads the data to a few files", :constraint => 'slow'  do
        result = @api.query("Opportunity", "SELECT Id, Name FROM Opportunity")
        result[:filenames].should have_at_least(2).items
        result[:jobs_done].should_not be_empty

        result[:filenames].each do |filename|
          File.size?(filename).should be_true

          lines = CSV.read(filename)

          if lines.length > 1
            # first line should be the header
            lines[0].should eql(["Id", "Name"])

            # first id shouldn't be emtpy
            lines[1][0].should_not be_empty
          end
        end
      end
    end
    context "when you give it all the options" do
      it "downloads a single file" do
        tmp = Dir.mktmpdir
        frm = "2000-01-01"
        from = "#{frm}T00:00:00.000Z"
        t = "2020-01-01"
        to = "#{t}T00:00:00.000Z"
        result = @api.query(
          "Account",
          "SELECT Id, Name, Industry, Type FROM Account",
          :check_interval => 30,
          :directory_path => tmp,
          :created_from => from,
          :created_to => to,
          :single_batch => true,
          :count_lines => true
        )

        result[:filenames].should have(1).items
        result[:jobs_done].should_not be_empty

        filename = result[:filenames][0]

        File.size?(filename).should be_true
        lines = CSV.read(filename)

        # first line should be the header
        lines[0].should eql(["Id", "Name", "Industry", "Type"])

        # first id shouldn't be emtpy
        lines[1][0].should_not be_empty

        filename.should match(tmp)
        filename.should match(frm)
        filename.should match(t)
      end
    end
    context "when you give it a short time limit" do
      it "downloads some stuff is unfinished" do
        result = @api.query(
          "Task",
          "SELECT Id, Name, CreatedDate FROM Task",
          :time_limit => 60
        )
        result[:unfinished_subqueries].should_not be_empty
      end
    end
  end

  describe "start_query" do
    it "starts a query that finishes some time later" do
      query = @api.start_query("Opportunity",  "SELECT Id, Name, CreatedDate FROM Opportunity", :single_batch => true)

      # get a cofee
      sleep(60*2)

      # check the status
      result = query.get_available_results
      expect(result[:finished]).to eq true
      result[:filenames].should have_at_least(1).items
      result[:jobs_done].should_not be_empty
    end

  end
end
