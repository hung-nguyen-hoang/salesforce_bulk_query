# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib/", __FILE__)
require "salesforce_bulk_query/version"

Gem::Specification.new do |s|
  s.name = 'salesforce_bulk_query'
  s.version = SalesforceBulkQuery::VERSION
  s.authors = ['Petr Cvengros']
  s.email = ['petr.cvengros@gooddata.com']

  s.homepage = 'https://github.com/cvengros/salesforce_bulk_query'
  s.summary = %q{Ruby wrapper over the Salesforce Bulk Query API}
  s.description = %q{It's awesome}

  s.add_dependency 'json'
  s.add_dependency 'xml-simple'


  s.files = `git ls-files`.split($/)
  s.require_paths = ['lib']

  s.rubygems_version = "1.3.7"
end
