require 'salesforce_bulk_query/connection'
require 'salesforce_bulk_query/job'


module SalesforceBulkQuery

  class Api
    @@DEFAULT_API_VERSION = '29.0'

    def initialize(client, api_version=nil)
      api_version ||= @@DEFAULT_API_VERSION
      @connection = SalesforceBulkQuery::Connection.new(client, api_version)
    end

    def instance_url
      # make sure it ends with /
      url = @connection.client.instance_url
      url += '/' if url[-1] != '/'
      return url
    end

    def query(sobject, soql)
      # TODO kdyz je v soqlu where nebo order by tak nasrat

      # create the job
      job = SalesforceBulkQuery::Job.new(sobject, @connection)
      job.create_job

      # get the date when the first was created
      min_created_resp = @connection.client.query("SELECT CreatedDate FROM #{sobject} ORDER BY CreatedDate LIMIT 1")
      min_created = nil
      min_created_resp.each {|s| min_created = s[:CreatedDate]}

      # generate intervals
      start = DateTime.parse(min_created)
      stop = DateTime.now
      step_size = (stop - start) / BATHES

      interval_beginings = start.step(stop, step_size).map{|f|f}
      interval_ends = interval_beginings.clone
      interval_ends.shift
      interval_ends.push(stop)

      interval_beginings.zip(interval_ends).each do |from, to|

        soql = query + " WHERE CreatedDate >= #{from} AND CreatedDate <= #{to}"
        puts "Adding soql #{soql} as a batch to job"
        job.add_query(soql)
      end

      close_response = job.close_job
      batch_responses = job.get_job_result(true, timeout)


      return close_response.merge({"batches" => batch_responses})
    end
  end
end