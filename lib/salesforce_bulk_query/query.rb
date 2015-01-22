require 'salesforce_bulk_query/job'
require 'date'

module SalesforceBulkQuery

  # Abstraction of a single user-given query. It contains multiple jobs, is tied to a specific connection
  class Query

    # if no created_to is given we use the current time with this offset
    # subtracted (to make sure the freshest changes that can be inconsistent
    # aren't there) It's in minutes
    OFFSET_FROM_NOW = 10

    def initialize(sobject, soql, connection, options={})
      @sobject = sobject
      @soql = soql
      @connection = connection
      @logger = options[:logger]
      @created_from = options[:created_from]
      @created_to = options[:created_to]
      @single_batch = options[:single_batch]

      # jobs currently running
      @jobs_in_progress = []

      # successfully finished jobs with no batches to split
      @jobs_done = []

      # finished or timeouted jobs with some batches split into other jobs
      @jobs_restarted = []

      @finished_batch_filenames = []
      @restarted_subqueries = []
    end

    attr_reader :jobs_in_progress, :jobs_restarted, :jobs_done

    DEFAULT_MIN_CREATED = "1999-01-01T00:00:00.000Z"

    # Creates the first job, divides the query to subqueries, puts all the subqueries as batches to the job
    def start(options={})
      # order by and where not allowed
      if (!@single_batch) && (@soql =~ /WHERE/i || @soql =~ /ORDER BY/i)
        raise "You can't have WHERE or ORDER BY in your soql. If you want to download just specific date range use created_from / created_to"
      end

      # create the first job
      job = SalesforceBulkQuery::Job.new(@sobject, @connection, {:logger => @logger}.merge(options))
      job.create_job

      # get the date when it should start
      if @created_from
        min_created = @created_from
      else
        # get the date when the first was created
        min_created = nil
        begin
          min_created_resp = @connection.client.query("SELECT CreatedDate FROM #{@sobject} ORDER BY CreatedDate LIMIT 1")
          min_created_resp.each {|s| min_created = s[:CreatedDate]}
        rescue Faraday::Error::TimeoutError => e
          @logger.warn "Timeout getting the oldest object for #{@sobject}. Error: #{e}. Using the default value" if @logger
          min_created = DEFAULT_MIN_CREATED
        end
      end

      # generate intervals
      start = DateTime.parse(min_created)
      stop = @created_to ? DateTime.parse(@created_to) : DateTime.now - Rational(options[:offset_from_now] || OFFSET_FROM_NOW, 1440)
      job.generate_batches(@soql, start, stop, @single_batch)

      job.close_job

      @jobs_in_progress.push(job)
    end

    # Get results for all finished jobs. If there are some unfinished batches, skip them and return them as unfinished.
    #
    # @param options[:directory_path]
    def get_available_results(options={})

      all_done = true
      unfinished_subqueries = []
      jobs_in_progress = []
      jobs_restarted = []
      jobs_done = []

      # check all jobs statuses and split what should be split
      @jobs_in_progress.each do |job|

        # check job status
        job_status = job.check_status
        job_over_limit = job.over_limit?
        job_done = job_status[:succeeded] || job_over_limit

        # download what's available
        job_results = job.get_available_results(options)
        unfinished_batches = job_results[:unfinished_batches]
        unfinished_subqueries += unfinished_batches.map {|b| b.soql}

        # split to subqueries what needs to be split
        to_split = job_results[:verification_fail_batches]
        to_split += unfinished_batches if job_over_limit

        # delete files associated with batches that failed verification
        job_results[:verification_fail_batches].each do |b|
          @logger.info "Deleting #{b.filename}, verification failed."
          File.delete(b.filename)
        end

#         unless to_split.empty?
# require 'pry'; binding.pry
#         end


        to_split.each do |batch|
          # for each unfinished batch create a new job and add it to new jobs
          @logger.info "The following subquery didn't end in time / failed verification: #{batch.soql}. Dividing into multiple and running again" if @logger
          new_job = SalesforceBulkQuery::Job.new(@sobject, @connection, {:logger => @logger}.merge(options))
          new_job.create_job
          new_job.generate_batches(@soql, batch.start, batch.stop)
          new_job.close_job
          jobs_in_progress.push(new_job)
        end

        # what to do with the current job
        # finish, some stuff restarted
        if job_done
          if to_split.empty?
            # done, nothing left
            jobs_done.push(job)
          else
            # done, some batches needed to be restarted
            jobs_restarted.push(job)
          end

          # store the filenames and restarted stuff
          @finished_batch_filenames += job_results[:filenames]
          @restarted_subqueries += to_split.map {|b| b.soql}
        else
          # still in progress
          jobs_in_progress.push(job)
        end

        # we're done if this job is done and it didn't generate any new jobs
        all_done &&= (job_done && to_split.empty?)
      end

      # remove the finished jobs from progress and add there the new ones
      @jobs_in_progress = jobs_in_progress
      @jobs_done += jobs_done

      return {
        :succeeded => all_done,
        :filenames => @finished_batch_filenames,
        :unfinished_subqueries => unfinished_subqueries,
        :jobs_done => @jobs_done.map { |j| j.job_id }
      }
    end
  end
end
