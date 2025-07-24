# frozen_string_literal: true

# This script takes the old carrier legal name and the new legal name and initiates the carrier rebranding operation.

# Command to trigger the script:
# CLIENT=me bundle exec rails runner script/products/rebrand_carrier.rb 'Old Carrier Name' 'New Carrier Name'

unless ARGV[0].present? && ARGV[1].present?
  puts 'Missing Arguments: Please provide old and new carrier names.'
  exit
end

old_name = ARGV[0]
new_name = ARGV[1]

result = ::Operations::Products::RebrandCarrier.new.call({ old_name: old_name, new_name: new_name })

if result.success?
  puts "Carrier rebranding successful: #{result.success}"
else
  puts "Carrier rebranding failed: #{result.failure}"
end
