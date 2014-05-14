require 'salesforce_bulk_query/job'

module SalesforceBulkQuery
  class Query

    def initialize(sobject, soql, connection, options)
      @sobject = sobject
      @soql = soql
      @connection = connection
      @logger = options[:logger]
      @jobs = []
      @finished_batch_filenames = []
      @restarted_subqueries = []
    end

    DEFAULT_MIN_CREATED = "1999-01-01T00:00:00.000Z"

    # creates the first job, divides the query to subqueries, puts all the subqueries as batches to the job
    def start
      # TODO kdyz je v soqlu where nebo order by tak nasrat

      # create the first job
      job = SalesforceBulkQuery::Job.new(@sobject, @connection)
      job.create_job

      # get the date when the first was created
      min_created = nil
      begin
        min_created_resp = @connection.client.query("SELECT CreatedDate FROM #{@sobject} ORDER BY CreatedDate LIMIT 1")
        min_created_resp.each {|s| min_created = s[:CreatedDate]}
      rescue Faraday::Error::TimeoutError => e
        @logger.warn "Timeout getting the oldest object for #{@sobject}. Error: #{e}. Using the default value" if @logger
        min_created = DEFAULT_MIN_CREATED
      end

      # generate intervals
      start = DateTime.parse(min_created)
      stop = DateTime.now
      job.generate_batches(@soql, start, stop)

      job.close_job

      @jobs.push(job)
    end


    # check statuses of all jobs
    def check_status
      all_done = true
      job_statuses = []
      # check all jobs statuses and put them in an array
      @jobs.each do |job|
        job_status = job.check_status
        all_done &&= job_status[:finished]
        job_statuses.push(job_status)
      end

      return {
        :finished => all_done,
        :job_statuses => job_statuses
      }
    end

    # get results for all jobs
    def get_results(options)
      all_job_results = []
      job_result_filenames = []
      unfinished_subqueries = []
      # check each job and put it there
      @jobs.each do |job|
        job_results = job.get_results(options)
        all_job_results.push(job_results)
        job_result_filenames += job_results[:filenames]
        unfinished_subqueries.push(job_results[:unfinished_batches].map {|b| b.soql})
      end
      return {
        :filenames => job_result_filenames + @finished_batch_filenames,
        :unfinished_subqueries => unfinished_subqueries,
        :restarted_subqueries => @restarted_subqueries,
        :results => all_job_results
      }
    end

    # restarts unfinished batches in a job, creating new jobs
    # downloads results for finished batches
    def get_result_or_restart(options)
      new_jobs = []
      @jobs.each do |job|
        # get available stuff, if not the right time yet, go on
        available_results = job.get_available_results(options)
        if available_results.nil?
          next
        end

        unfinished_batches = available_results[:unfinished_batches]

        # store the filenames and resturted stuff
        @finished_batch_filenames += available_results[:filenames]
        @restarted_subqueries += unfinished_batches.map {|b| b.soql}

        unfinished_batches.each do |batch|
          # for each unfinished batch create a new job and add it to new jobs
          @logger.info "The following subquery didn't end in time: #{batch.soql}. Dividing into multiple and running again" if @logger
          new_job = SalesforceBulkQuery::Job.new(@sobject, @connection)
          new_job.create_job
          new_job.generate_batches(@soql, batch.start, batch.stop)
          new_job.close_job
          new_jobs.push(new_job)
require 'pry'; binding.pry
        end
      end
      @jobs += new_jobs
    end
  end
end