require "salesforce_bulk_query/batch"

module SalesforceBulkQuery

  # Represents a Salesforce bulk api job, contains multiple batches.
  # Many jobs contained in Query
  class Job
    @@operation = 'query'
    @@xml_header = '<?xml version="1.0" encoding="utf-8" ?>'
    JOB_TIME_LIMIT = 15 * 60
    BATCH_COUNT = 15


    def initialize(sobject, connection, options={})
      @sobject = sobject
      @connection = connection
      @logger = options[:logger]
      @job_time_limit = options[:job_time_limit] || JOB_TIME_LIMIT
      @date_field = options[:date_field] or fail "date_field must be given when creating a batch"

      # all batches (static)
      @batches = []

      # unfinished batches as of last get_available_results call
      @unfinished_batches = []

      # filenames fort the already downloaded and verified batches
      @filenames = []
    end

    attr_reader :job_id

    # Do the API request
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

    def get_extended_soql(soql, from, to)
      return "#{soql} WHERE #{@date_field} >= #{from} AND #{@date_field} < #{to}"
    end

    def generate_batches(soql, start, stop, single_batch=false)
      # if there's just one batch wanted, add it and we're done
      if single_batch
        soql_extended = get_extended_soql(soql, start, stop)
        @logger.info "Adding soql #{soql_extended} as a batch to job" if @logger

        add_query(soql_extended,
          :start => start,
          :stop => stop
        )
        return
      end

      # if there's more, generate the time intervals and generate the batches
      step_size = (stop - start) / BATCH_COUNT

      interval_beginings = start.step(stop - step_size, step_size).map{|f|f}
      interval_ends = interval_beginings.clone
      interval_ends.shift
      interval_ends.push(stop)

      interval_beginings.zip(interval_ends).each do |from, to|

        soql_extended = get_extended_soql(soql, from, to)
        @logger.info "Adding soql #{soql_extended} as a batch to job" if @logger

        add_query(soql_extended,
          :start => from,
          :stop => to
        )
      end
    end

    def add_query(query, options={})
      # create and create a batch
      batch = SalesforceBulkQuery::Batch.new(
        :sobject => @sobject,
        :soql => query,
        :job_id => @job_id,
        :connection => @connection,
        :start => options[:start],
        :stop => options[:stop],
        :logger => @logger,
        :date_field => @date_field
      )
      batch.create

      # add the batch to the list
      @batches.push(batch)
      @unfinished_batches.push(batch)
    end

    def close_job
      xml = "#{@@xml_header}<jobInfo xmlns=\"http://www.force.com/2009/06/asyncapi/dataload\">"
      xml += "<state>Closed</state>"
      xml += "</jobInfo>"

      path = "job/#{@job_id}"

      response_parsed = @connection.post_xml(path, xml)
      @job_closed_time = Time.now
    end

    def check_status
      path = "job/#{@job_id}"
      response_parsed = @connection.get_xml(path)
      @completed_count = Integer(response_parsed["numberBatchesCompleted"][0])
      @succeeded = @completed_count == Integer(response_parsed["numberBatchesTotal"][0])

      return {
        :succeeded => @succeeded,
        :some_records_failed => Integer(response_parsed["numberRecordsFailed"][0]) > 0,
        :some_batches_failed => Integer(response_parsed["numberBatchesFailed"][0]) > 0,
        :response => response_parsed
      }
    end

    def over_limit?
      (Time.now - @job_closed_time) > @job_time_limit
    end

    # downloads whatever is available, returns as unfinished whatever is not

    def get_available_results(options={})
      downloaded_filenames = []
      unfinished_batches = []
      verification_fail_batches = []
      failed_batches = []

      # get result for each batch in the job
      @unfinished_batches.each do |batch|
        batch_status = batch.check_status

        # if the result is ready
        if batch_status[:succeeded]
          # each finished batch should go here only once

          # download the result
          result = batch.get_result(options)
          @logger.info "get_result result: #{result}" if @logger

          # if the verification failed, put it to failed
          # will never ask about this one again.
          if result[:verification] == false
            verification_fail_batches << batch
          else
            # if verification ok and finished put it to filenames
            downloaded_filenames << result[:filename]
          end
        elsif batch_status[:failed]
          # put it to failed and raise error at the end
          failed_batches << batch
        else
          # otherwise put it to unfinished
          unfinished_batches << batch
        end
      end

      unless failed_batches.empty?
        details = failed_batches.map{ |b| "#{b.batch_id}: #{b.fail_message}"}.join("\n")
        fail ArgumentError, "#{failed_batches.length} batches failed. Details: #{details}"
      end

      # cache the unfinished_batches till the next run
      @unfinished_batches = unfinished_batches

      # cumulate filenames
      @filenames += downloaded_filenames

      @logger.info "unfinished batches: #{unfinished_batches}\nverification_fail_batches: #{verification_fail_batches}" if @logger

      return {
        :finished => @unfinished_batches.empty?,
        :filenames => @filenames,
        :unfinished_batches => @unfinished_batches,
        :verification_fail_batches => verification_fail_batches
      }
    end

    def to_log
      return {
        :sobject => @sobject,
        :connection => @connection.to_log,
        :batches => @batches.map {|b| b.to_log},
        :unfinished_batches => @unfinished_batches.map {|b| b.to_log}
      }
    end
  end
end
