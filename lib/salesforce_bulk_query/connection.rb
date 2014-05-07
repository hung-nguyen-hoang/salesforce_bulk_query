module SalesforceBulkQuery
  class Connection
    def initialize(client, api_version)
      @client=client

      @@API_VERSION = api_version
      @@PATH_PREFIX = "/services/async/#{@@API_VERSION}/"
    end

    def post_xml(host, path, xml, headers)
require 'pry'; binding.pry
      host = host || @@INSTANCE_HOST
      if host != @@LOGIN_HOST # Not login, need to add session id to header
        headers['X-SFDC-Session'] = @session_id;
        path = "#{@@PATH_PREFIX}#{path}"
      end
      i = 0
      begin
        https(host).post(path, xml, headers).body
      rescue
        i += 1
        if i < 3
          puts "Request fail #{i}: Retrying #{path}"
          retry
        else
          puts "FATAL: Request to #{path} failed three times."
          raise
        end
      end
    end
  end
end