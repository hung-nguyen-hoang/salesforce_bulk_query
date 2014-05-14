require 'salesforce_bulk_query/connection'
require 'salesforce_bulk_query/query'
require 'salesforce_bulk_query/logger'


module SalesforceBulkQuery

  class Api
    @@DEFAULT_API_VERSION = '29.0'

    def initialize(client, options)
      api_version = options[:api_version] || @@DEFAULT_API_VERSION

      # use our own logging middleware if logger passed
      if options[:logger]
        client.middleware.use(SalesforceBulkQuery::Logger,options[:logger], options)
        # switch off the normal logging
        restforce_class = client.class.parent.parent
        restforce_class.log = false if restforce_class.respond_to?(:log)
        @logger = options[:logger]
      end

      # initialize connection
      @connection = SalesforceBulkQuery::Connection.new(client, api_version)
    end

    def instance_url
      # make sure it ends with /
      url = @connection.client.instance_url
      url += '/' if url[-1] != '/'
      return url
    end

    CHECK_INTERVAL = 10
    QUERY_TIME_LIMIT = 60 * 60 * 2 # two hours

    # blocking method - waits until the query is resolved
    # can take quite some time
    def query(sobject, soql, options={})
      # TODO default for options[:directory_path]
      check_interval = options[:check_interval] || CHECK_INTERVAL
      time_limit = options[:time_limit] || QUERY_TIME_LIMIT

      start_time = Time.now

      # start the machinery
      query = start_query(sobject, soql)
      results = nil

      loop do
        # check the status
        status = query.check_status

        # if finished get the result and we're done
        if status[:finished]

          # get the results and we're done
          results = query.get_results(:directory_path => options[:directory_path])
          @logger.info "Query finished. Results: #{results}"
          break
        end

        # if we've run out of time limit, go away
        if Time.now - start_time > QUERY_TIME_LIMIT
          @logger.warn "Ran out of time limit, downloading what's available and terminating" if @logger

          # download what's available
          results = query.get_results(
            :directory_path => options[:directory_path],
          )

          @logger.info "Downloaded the following files: #{results[:filenames]} The following didn't finish in time: #{results[:unfinished_subqueries]}" if @logger
          break
        end

        # restart whatever needs to be restarted and sleep
        query.get_result_or_restart(:directory_path => options[:directory_path])
        @logger.info "Sleeping" if @logger
        sleep(check_interval)
      end

      return results
    end

    def start_query(sobject, soql)
      # create the query, start it and return it
      query = SalesforceBulkQuery::Query.new(sobject, soql, @connection, :logger => @logger)
      query.start
      return query
    end
  end
end