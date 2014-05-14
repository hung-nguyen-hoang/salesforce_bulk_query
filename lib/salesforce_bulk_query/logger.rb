# custom logger logging just small enough response bodies
require 'forwardable'
require 'faraday'

module SalesforceBulkQuery
  class Logger < Faraday::Response::Middleware
    extend Forwardable

    MAX_LOG_LENGTH = 2000

    def initialize(app, logger, options)
      super(app)
      @options = options
      @logger = logger || begin
        require 'logger'
        ::Logger.new(STDOUT)
      end
    end

    def_delegators :@logger, :debug, :info, :warn, :error, :fatal

    def call(env)
      debug('request') do
        dump :url => env[:url].to_s,
          :method => env[:method],
          :headers => env[:request_headers],
          :body => env[:body][0..MAX_LOG_LENGTH]
      end
      super
    end

    def on_complete(env)
      debug('response') do
        dump :status => env[:status].to_s,
          :headers => env[:response_headers],
          :body => env[:body][0..MAX_LOG_LENGTH]
      end
    end

    def dump(hash)
      "\n" + hash.map { |k, v| " #{k}: #{v.inspect}" }.join("\n")
    end
  end
end