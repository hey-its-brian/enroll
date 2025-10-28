# frozen_string_literal: true

# This script takes family member IDs and removes duplicate family members.

# Command to trigger the script:
# bundle exec rails runner script/remove_duplicate_family_members.rb family_member_id1 family_member_id2 family_member_id3

require File.join(Rails.root, 'lib', 'remove_family_member')

family_member_ids = ARGV

class Remover
  include RemoveFamilyMember
end

success, messages = Remover.new.remove_duplicate_members(family_member_ids)
if success
  messages.each { |msg| puts msg }
else
  messages.each { |msg| puts msg }
end

