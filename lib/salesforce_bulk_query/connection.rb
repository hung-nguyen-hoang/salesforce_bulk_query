require 'xmlsimple'

module SalesforceBulkQuery
  class Connection
    def initialize(client, api_version, logger=nil)
      @client=client
      @logger = logger

      @@API_VERSION = api_version
      @@PATH_PREFIX = "/services/async/#{@@API_VERSION}/"
    end

    attr_reader :client

    XML_REQUEST_HEADER = {'Content-Type' => 'application/xml; charset=utf-8'}
    CSV_REQUEST_HEADER = {'Content-Type' => 'text/csv; charset=UTF-8'}

    def session_header
      {'X-SFDC-Session' => @client.options[:oauth_token]}
    end

    def parse_xml(xml)
      begin
        return XmlSimple.xml_in(xml)
      rescue => e
        @logger.error "Error parsing xml: #{xml}\n#{e}\n#{e.backtrace}"
        raise
      end
    end

    def post_xml(path, xml, options={})
      path = "#{@@PATH_PREFIX}#{path}"
      headers = options[:csv_content_type] ? CSV_REQUEST_HEADER : XML_REQUEST_HEADER

      response = nil
      # do the request
      with_retries do
        response = @client.post(path, xml, headers.merge(session_header))
      end

      return parse_xml(response.body)
    end

    def get_xml(path, options={})
      path = "#{@@PATH_PREFIX}#{path}"
      headers = XML_REQUEST_HEADER

      response = nil
      with_retries do
        response = @client.get(path, {}, headers.merge(session_header))
      end

      return options[:skip_parsing] ? response.body : parse_xml(response.body)
    end

    def with_retries
      i = 0
      begin
        yield
      rescue => e
        i += 1
        if i < 3
          @logger.warn "Retrying, got error: #{e}, #{e.backtrace}" if @logger
          retry
        else
          @logger.error "Failed 3 times, last error: #{e}, #{e.backtrace}" if @logger
          raise
        end
      end
    end
  end
end