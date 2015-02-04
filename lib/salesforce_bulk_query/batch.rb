require 'tmpdir'

require 'salesforce_bulk_query/utils'


module SalesforceBulkQuery
  # Represents a Salesforce api batch. Batch contains a single subquery.
  # Many batches are contained in a Job.
  class Batch
    def initialize(options)
      @sobject = options[:sobject]
      @soql = options[:soql]
      @job_id = options[:job_id]
      @connection = options[:connection]
      @date_field = options[:date_field] or fail "date_field must be given when creating a batch"
      @start = options[:start]
      @stop = options[:stop]
      @logger = options[:logger]
      @@directory_path ||= Dir.mktmpdir
      @filename = nil
    end

    attr_reader :soql, :start, :stop, :filename, :fail_message, :batch_id, :csv_record_count

    # Do the api request
    def create
      path = "job/#{@job_id}/batch/"

      response_parsed = @connection.post_xml(path, @soql, {:csv_content_type => true})

      @batch_id = response_parsed['id'][0]
    end

    # check status of the batch
    # if it fails, don't throw an error now, let the job above collect all fails and raise it at once
    def check_status
      succeeded = nil
      failed = nil

      # get the status of the batch
      # https://www.salesforce.com/us/developer/docs/api_asynch/Content/asynch_api_batches_get_info.htm
      status_path = "job/#{@job_id}/batch/#{@batch_id}"
      status_response = @connection.get_xml(status_path)

      # interpret the status
      @status = status_response['state'][0]

      # https://www.salesforce.com/us/developer/docs/api_asynch/Content/asynch_api_batches_interpret_status.htm
      case @status
        when 'Failed'
          failed = true
          @fail_message = status_response['stateMessage']
        when 'InProgress', 'Queued'
          succeeded = false
        when 'Completed'
          succeeded = true
          failed = false
        else
          fail "Something weird happened, #{@batch_id} has status #{@status}."
      end

      if succeeded
        # request to get the result id
        # https://www.salesforce.com/us/developer/docs/api_asynch/Content/asynch_api_batches_get_results.htm
        path = "job/#{@job_id}/batch/#{@batch_id}/result"

        response_parsed = @connection.get_xml(path)

        @result_id = response_parsed["result"] ? response_parsed["result"][0] : nil
      end

      return {
        :failed => failed,
        :fail_message => @fail_message,
        :succeeded => succeeded,
        :result_id => @result_id
      }
    end

    def get_filename
      return "#{@sobject}_#{@date_field}_#{@start}_#{@stop}_#{@batch_id}.csv"
    end

    def get_result(options={})
      # if it was already downloaded, no one should ask about it
      if @filename
        raise "This batch was already downloaded once: #{@filename}, #{@batch_id}"
      end

      directory_path = options[:directory_path]
      skip_verification = options[:skip_verification]

      # request to get the actual results
      path = "job/#{@job_id}/batch/#{@batch_id}/result/#{@result_id}"

      if !@result_id
        raise "batch #{@batch_id} not finished yet, trying to get result: #{path}"
      end

      directory_path ||= @@directory_path

      # write it to a file
      @filename = File.join(directory_path, get_filename)
      @connection.get_to_file(path, @filename)

      # Verify the number of downloaded records is roughly the same as
      # count on the soql api
      # maybe also verify
      unless skip_verification
        verify
      end
      @logger.debug "get_result :verification : #{@verification}" if @logger
      return {
        :filename => @filename,
        :verification => @verification
      }
    end

    def verify
      api_count = @connection.query_count(@sobject, @date_field, @start, @stop)
      # if we weren't able to get the count, fail.
      if api_count.nil?
        return @verification = false
      end

      # count the records in the csv
      @csv_record_count = Utils.line_count(@filename)

      if @logger && @csv_record_count > 0 && @csv_record_count % 100 == 0
        @logger.warn "The line count for batch id #{@batch_id} soql #{@soql} is highly suspicious: #{@csv_record_count}"
      end
      if @logger && @csv_record_count != api_count
        @logger.warn "The counts for batch id #{@batch_id}, soql #{@soql} don't match. Record count in downloaded csv #{@csv_record_count}, record count on api count(): #{api_count}"
        @logger.info "verify result: #{@csv_record_count >= api_count}"

      end
      @verification = (@csv_record_count >= api_count)
    end

    def to_log
      return {
        :sobject => @sobject,
        :soql => @soql,
        :job_id => @job_id,
        :connection => @connection.to_log,
        :start => @start,
        :stop => @stop,
        :directory_path => @@directory_path
      }
    end
  end
end
