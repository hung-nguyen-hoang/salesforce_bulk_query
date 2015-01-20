require 'csv'

module SalesforceBulkQuery
  class Utils
    # record count if they want to
    def self.line_count(f)
      i = 0
      CSV.foreach(f, :headers => true) {|_| i += 1}
      i
    end
  end
end