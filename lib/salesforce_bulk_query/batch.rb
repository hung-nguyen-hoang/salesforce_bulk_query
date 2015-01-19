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
      @start = options[:start]
      @stop = options[:stop]
      @@directory_path ||= Dir.mktmpdir
    end

    attr_reader :soql, :start, :stop

    # Do the api request
    def create
      path = "job/#{@job_id}/batch/"

      response_parsed = @connection.post_xml(path, @soql, {:csv_content_type => true})

      @batch_id = response_parsed['id'][0]
    end

    def check_status
      # request to get the result id
      path = "job/#{@job_id}/batch/#{@batch_id}/result"

      response_parsed = @connection.get_xml(path)

      @result_id = response_parsed["result"] ? response_parsed["result"][0] : nil
      return {
        :finished => ! @result_id.nil?,
        :result_id => @result_id
      }
    end

    def get_filename
      return "#{@sobject}_#{@batch_id}_#{@start}-#{@stop}.csv"
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
        raise "batch not finished yet, trying to get result: #{path}"
      end

      directory_path ||= @@directory_path

      # write it to a file
      @filename = File.join(directory_path, get_filename)
      @connection.get_to_file(path, @filename)

      # Verify the number of downloaded records is roughly the same as
      # count on the soql api
      unless skip_verification
        api_count = @connection.query_count(@sobject, @start, @stop)
        # if we weren't able to get the count, fail.
        if api_count.nil?
          @verfication = false
        else
          # count the records in the csv
          csv_count = Utils.line_count(@filename)
          @verfication = csv_count >= api_count
        end
      end

      return {
        :filename => @filename,
        :verfication => @verfication
      }
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
