module SalesforceBulkQuery
  class Job
    @@operation = 'query'
    @@xml_header = '<?xml version="1.0" encoding="utf-8" ?>'

    def initialize(sobject, connection)
      @sobject = sobject
      @connection = connection
      @batch_ids = []
      create_job
    end

    attr_reader :job_id


    def create_job(csv=true)
      content_type = csv ? "CSV" : "XML"
      xml = "#{@@xml_header}<jobInfo xmlns=\"http://www.force.com/2009/06/asyncapi/dataload\">"
      xml += "<operation>#{@@operation}</operation>"
      xml += "<object>#{@sobject}</object>"
      xml += "<contentType>#{content_type}</contentType>"
      xml += "</jobInfo>"

      response_parsed = @connection.post_xml("job", xml)
      @job_id = response_parsed['id'][0]
    end

    def add_query(query)
      path = "job/#{@job_id}/batch/"

      response_parsed = @connection.post_xml(path, query, {:csv_content_type => true})
      # add the batch id to the list
      @batch_ids << response_parsed['id'][0]
    end

    def close_job
      xml = "#{@@xml_header}<jobInfo xmlns=\"http://www.force.com/2009/06/asyncapi/dataload\">"
      xml += "<state>Closed</state>"
      xml += "</jobInfo>"

      path = "job/#{@job_id}"

      response_parsed = @connection.post_xml(path, xml)
    end

    def check_job_status
      path = "job/#{@job_id}"
      response_parsed = @connection.get_xml(path)
      @finished = Integer(response_parsed["numberBatchesCompleted"][0]) == Integer(response_parsed["numberBatchesTotal"][0])
      return {
        "finished" => @finished,
        "some_failed" => Integer(response_parsed["numberRecordsFailed"][0]) > 0,
        "response" => response_parsed
      }
    end

    def get_batch_result(batch_id, directory_path)
      # request to get the result id
      path = "job/#{@job_id}/batch/#{batch_id}/result"

      response_parsed = @connection.get_xml(path)

      # request to get the actual results
      result_id = response_parsed["result"][0]
      path2 = "job/#{@job_id}/batch/#{batch_id}/result/#{result_id}"

      response = @connection.get_xml(path2, :skip_parsing => true)

      # write it to a file
      filename = File.join(directory_path, "#{@sobject}-#{batch_id}.csv")
      File.open(filename, 'w') { |file| file.write(response) }

      return filename
    end

    def get_job_results(options)
      if !@finished
        raise "the job #{@job_id} isn't finished yet"
      end

      # get result for each batch in the job
      result_filenames = []
      @batch_ids.each do |batch_id|
        batch_result = get_batch_result(batch_id, options[:directory_path])
        result_filenames.push(batch_result)
      end

      return result_filenames
    end
  end
end
