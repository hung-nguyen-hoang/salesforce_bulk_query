#!/bin/sh

# get the new version
VERSION=`bundle exec ruby <<-EORUBY

  require 'salesforce_bulk_query'
  puts SalesforceBulkQuery::VERSION

EORUBY`

# create tag and push it
TAG="v$VERSION"
git tag $TAG
git push origin $TAG

# build and push the gem
gem build salesforce_bulk_query.gemspec
gem push "salesforce_bulk_query-$VERSION.gem"

# update the gem after a few secs
wait 30
gem update salesforce_bulk_query