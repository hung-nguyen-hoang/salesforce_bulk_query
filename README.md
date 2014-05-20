Salesforce Bulk Query
=====================
A library for downloading data from Salesforce Bulk API. We only focus on querying, other operations of the API aren't supported. Designed to handle a lot of data.

Derived from [Salesforce Bulk API](https://github.com/yatish27/salesforce_bulk_api)

## Basic Usage
    require 'restforce'
    require 'salesforce_bulk_query'

    # Create a bulk query instance
    # with basic auth
    restforce = Restforce.new(
      :username => 'me',
      :password => 'password',
      :security_token => 'token',
      :client_id => "my sfdc app client id",
      :client_secret => "my sfdc app client secret"
    )

    # or OAuth
    restforce = Restforce.new(
      :refresh_token => "xyz",
      :client_id => "my sfdc app client id",
      :client_secret => "my sfdc app client secret"
    )

    bulk_api = SalesforceBulkQuery::Api.new(restforce)

    # query the api
    result = bulk_client.query("Task", "SELECT Id, Name FROM Task")

    # the result is files 
    puts "All the downloaded stuff is in csvs: #{result[:filenames]}"

    # query is a blocking call and can take several hours
    # if you want to just start the query asynchronously, use 
    query = start_query("Task", "SELECT Id, Name FROM Task")

    # get a cofee

    # check the status
    status = query.check_status
    if status[:finished]
      result = query.get_results
      puts "All the downloaded stuff is in csvs: #{result[:filenames]}"
    end

## How it works

The library uses the [Salesforce Bulk API](https://www.salesforce.com/us/developer/docs/api_asynch/index_Left.htm#CSHID=asynch_api_bulk_query.htm|StartTopic=Content%2Fasynch_api_bulk_query.htm|SkinName=webhelp). The given query is divided into 15 subqueries, according to the [limits](http://www.salesforce.com/us/developer/docs/api_asynchpre/index_Left.htm#CSHID=asynch_api_concepts_limits.htm|StartTopic=Content%2Fasynch_api_concepts_limits.htm|SkinName=webhelp). Each subquery is an interval based on the CreatedDate Salesforce field. The limits are passed to the API in SOQL queries. Subqueries are sent to the API as batches and added to a job. 

The first interval starts with the date the first Salesforce object was created, we query Salesforce REST API for that. If this query times out, we use a constant. The last interval ends a few minutes before now to avoid consistency issues. Custom start and end can be passed - see Options.

Job has a fixed time limit to process all the subqueries. Batches that finish in time are downloaded to CSVs, batches that don't are divided to 15 subqueries each and added to new jobs.

CSV results are downloaded by chunks, so that we don't run into memory related issues. All other requests are made through the Restforce client that is passed when instantiating the Api class. Restforce is not in the dependencies, so theoretically you can pass another object with the same set of methods as Restforce client.

## Options
There are a few optional settings you can pass to the `Api` methods:
* `api_version`: which Salesforce api version should be used
* `logger`: where logs should go
* `filename_prefix`: prefix applied to csv files
* `directory_path`: custom direcotory path for CSVs, if omitted, a new temp directory is created
* `check_interval`: how often the results should be checked in secs. 
* `time_limit`: maximum time the query can take. If this time limit is exceeded, available results are downloaded and the list of subqueries that didn't finished is returned
* `created_from`, `created_to`: limits for the CreatedDate field. Note that queries can't contain any WHERE statements as we're doing some manipulations to create subqueries and we don't want things to get too difficult. So this is the way to limit the query yourself. The format is like `"1999-01-01T00:00:00.000Z"`
* `single_batch`: If true, the queries are not divided into subqueries as described above. Instead one batch job is created with the given query. 

See specs for exact usage.

## Copyright

Copyright (c) 2014 GoodData Corporation. See LICENSE for details.



