require "salesforce_bulk_query/batch"

module SalesforceBulkQuery
  class Job
    @@operation = 'query'
    @@xml_header = '<?xml version="1.0" encoding="utf-8" ?>'
    JOB_TIME_LIMIT = 10 * 60
    BATCH_COUNT = 15


    def initialize(sobject, connection)
      @sobject = sobject
      @connection = connection
      @batches = []
      @unfinished_batches = nil
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

    def generate_batches(soql, start, stop)
      step_size = (stop - start) / BATCH_COUNT

      interval_beginings = start.step(stop - step_size, step_size).map{|f|f}
      interval_ends = interval_beginings.clone
      interval_ends.shift
      interval_ends.push(stop)

      interval_beginings.zip(interval_ends).each do |from, to|

        soql_extended = "#{soql} WHERE CreatedDate >= #{from} AND CreatedDate < #{to}"
        puts "Adding soql #{soql_extended} as a batch to job"

        add_query(soql_extended,
          :start => from,
          :stop => to
        )
      end
    end

    def add_query(query, options)
      # create and create a batch
      batch = SalesforceBulkQuery::Batch.new(
        :sobject => @sobject,
        :soql => query,
        :job_id => @job_id,
        :connection => @connection,
        :start => options[:start],
        :stop => options[:stop]
      )
      batch.create

      # add the batch to the list
      @batches.push(batch)
    end

    def close_job
      xml = "#{@@xml_header}<jobInfo xmlns=\"http://www.force.com/2009/06/asyncapi/dataload\">"
      xml += "<state>Closed</state>"
      xml += "</jobInfo>"

      path = "job/#{@job_id}"

      response_parsed = @connection.post_xml(path, xml)
      @job_closed = Time.now
    end

    def check_status
      path = "job/#{@job_id}"
      response_parsed = @connection.get_xml(path)
      @completed = Integer(response_parsed["numberBatchesCompleted"][0])
      @finished = @completed == Integer(response_parsed["numberBatchesTotal"][0])
      return {
        :finished => @finished,
        :some_failed => Integer(response_parsed["numberRecordsFailed"][0]) > 0,
        :response => response_parsed
      }
    end

    # downloads whatever is available, returns as unfinished whatever is not
    def get_results(options)
      filenames = []
      unfinished_batches = []

      # get result for each batch in the job
      @batches.each do |batch|
        batch_status = batch.check_status

        # if the result is ready
        if batch_status[:finished]

          # download the result
          filename = batch.get_result(options[:directory_path])
          filenames.push(filename)
        else
          # otherwise put it to unfinished
          unfinished_batches.push(batch)
        end
      end
      @unfinished_batches = unfinished_batches

      return {
        :filenames => filenames,
        :unfinished_batches => unfinished_batches
      }
    end

    def get_available_results(options)
      # if we didn't reach limit yet, do nothing
      # if all done, do nothing
      # if none of the batches finished, same thing
      if (Time.now - @job_closed < JOB_TIME_LIMIT) || @finished || @completed == 0
        return nil
      end

      return get_results(options)
    end
  end
end
