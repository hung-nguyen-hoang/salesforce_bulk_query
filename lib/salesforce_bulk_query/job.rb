module SalesforceBulkQuery
  class Job
    @@operation = 'query'
    @@xml_header = '<?xml version="1.0" encoding="utf-8" ?>'

    def initialize(sobject, connection)
      @sobject        = sobject
      @connection     = connection
      @batch_ids      = []
    end

    def create_job
      xml = "#{@@xml_header}<jobInfo xmlns=\"http://www.force.com/2009/06/asyncapi/dataload\">"
      xml += "<operation>#{@@operation}</operation>"
      xml += "<object>#{@sobject}</object>"
      xml += "<contentType>XML</contentType>"
      xml += "</jobInfo>"

      path = "job"
      headers = Hash['Content-Type' => 'application/xml; charset=utf-8']

      response_parsed = @connection.post_xml(path, xml, headers)
      @job_id = response_parsed['id'][0]
    end
  end
end
