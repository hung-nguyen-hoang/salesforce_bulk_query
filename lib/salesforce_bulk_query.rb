require 'salesforce_bulk_query/connection'
require 'salesforce_bulk_query/job'


module SalesforceBulkQuery

  class Api
    @@DEFAULT_API_VERSION = '29.0'

    def initialize(client, options)
      api_version = options[:api_version] || @@DEFAULT_API_VERSION
      @connection = SalesforceBulkQuery::Connection.new(client, api_version)
      @logger = options[:logger]
    end

    def instance_url
      # make sure it ends with /
      url = @connection.client.instance_url
      url += '/' if url[-1] != '/'
      return url
    end

    BATCH_COUNT = 15
    DEFAULT_MIN_CREATED = "1999-01-01T00:00:00.000Z"

    def start_query(sobject, soql)
      # TODO kdyz je v soqlu where nebo order by tak nasrat

      # create the job
      job = SalesforceBulkQuery::Job.new(sobject, @connection)

      # get the date when the first was created
      min_created = nil
      begin
        min_created_resp = @connection.client.query("SELECT CreatedDate FROM #{sobject} ORDER BY CreatedDate LIMIT 1")
        min_created_resp.each {|s| min_created = s[:CreatedDate]}
      rescue Faraday::Error::TimeoutError => e
        @logger.warn "Timeout getting the oldest object for #{sobject}. Error: #{e}. Using the default value" if @logger
        min_created = DEFAULT_MIN_CREATED
      end

      # generate intervals
      start = DateTime.parse(min_created)
      stop = DateTime.now
      step_size = (stop - start) / BATCH_COUNT

      interval_beginings = start.step(stop, step_size).map{|f|f}
      interval_ends = interval_beginings.clone
      interval_ends.shift
      interval_ends.push(stop)

      interval_beginings.zip(interval_ends).each do |from, to|

        soql_extended = "#{soql} WHERE CreatedDate >= #{from} AND CreatedDate <= #{to}"
        puts "Adding soql #{soql_extended} as a batch to job"
        job.add_query(soql_extended)
      end

      job.close_job

      return job
    end
  end
end