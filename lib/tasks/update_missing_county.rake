require File.join(Rails.root, "app", "data_migrations", "update_missing_county")
# This rake task is to update address county when zip code is present
# RAILS_ENV=production bundle exec rake migrations:update_missing_county

namespace :migrations do
  desc "update county"
  UpdateMissingCounty.define_task :update_missing_county => :environment
end