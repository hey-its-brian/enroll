# frozen_string_literal: true

require File.join(
  Rails.root,
  "app",
  "data_migrations",
  "remove_duplicate_family_members"
)

# Usage examples:
#   RAILS_ENV=production bundle exec rake migrations:remove_duplicate_family_members hbx_ids=123,345,235
#   RAILS_ENV=production bundle exec rake migrations:remove_duplicate_family_members csv_file=/path/to/file.csv
#   RAILS_ENV=production bundle exec rake migrations:remove_duplicate_family_members \
#     hbx_ids=123,345,235 csv_file=/path/to/file.csv

namespace :migrations do
  desc "Remove duplicate family members for given HBX IDs (from inline CSV and/or CSV file)"
  RemoveDuplicateFamilyMembers.define_task :remove_duplicate_family_members => :environment do |_t, _args|
    RemoveDuplicateFamilyMembers.new("remove_duplicate_family_members", nil).migrate
  end
end
