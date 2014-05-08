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

    def post_xml(path, xml, headers)
      path = "#{@@PATH_PREFIX}#{path}"
      headers['X-SFDC-Session'] = @client.options[:oauth_token]

      # do the request
      i = 0
      begin
        response = @client.post(path, xml, headers)
      rescue => e
        i += 1
        if i < 3
          logger.warn "Retrying, got error: #{e}, #{e.backtrace}"
          retry
        else
          logger.error "Failed 3 times, last error: #{e}, #{e.backtrace}"
          raise
        end
      end

      response_parsed = XmlSimple.xml_in(response.body)
require 'pry'; binding.pry
      return response_parsed
    end
  end
end