module SalesforceBulkQuery
  class Batch
    def initialize(options)
      @sobject = options[:sobject]
      @soql = options[:soql]
      @job_id = options[:job_id]
      @connection = options[:connection]
      @start = options[:start]
      @stop = options[:stop]
    end

    attr_reader :soql, :start, :stop

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

    def get_result(directory_path)

      # request to get the actual results
      path = "job/#{@job_id}/batch/#{@batch_id}/result/#{@result_id}"

      if !@result_id
        raise "batch not finished yet, trying to get result: #{path}"
      end

      # write it to a file
      filename = File.join(directory_path, "#{@sobject}-#{@batch_id}.csv")
      @connection.get_to_file(path, filename)

      return filename
    end

  end
end