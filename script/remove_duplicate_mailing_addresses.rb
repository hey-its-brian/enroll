require 'csv'

# Cleanup + Report: destroy duplicate mailing addresses per person
# Usage (Rails runner):
#   bundle exec rails runner script/remove_duplicate_mailing_addresses.rb


def normalize(str)
  return '' if str.nil?
  str.to_s.strip.gsub(/\s+/, ' ').downcase
end

def address_signature(addr)
  [
    normalize(addr.address_1),
    normalize(addr.address_2),
    normalize(addr.city),
    normalize(addr.state),
    normalize(addr.zip)
  ].join('|')
end

timestamp = Time.current.strftime('%Y_%m_%d_%H%M%S')
output_path = (Rails.root.join("multiple_mailing_addresses_cleanup_#{timestamp}.csv")).to_s

headers = [
  'person_hbx_id',
  'duplicate_groups',
  'destroyed_count',
  'kept_address',
  'destroyed_addresses'
]

CSV.open(output_path, 'w') do |csv|
  csv << headers

  Person.where(:'addresses.kind' => 'mailing').each do |person|
    mailing = person.addresses.where(kind: 'mailing').to_a
    next if mailing.size < 2

    groups = mailing.group_by { |a| address_signature(a) }
    destroyed_total = 0

    groups.each_value do |group|
      next if group.size < 2

      address_to_keep = group.compact.sort_by { |a| a.created_at || Time.at(0) }.first
      addresses_to_destroy = group - [address_to_keep]
      destroyed_addrs = addresses_to_destroy.map { |a| [a.address_1, a.address_2, a.city, a.state, a.zip].compact.join(', ') }
      kept_str = [address_to_keep.address_1, address_to_keep.address_2, address_to_keep.city, address_to_keep.state, address_to_keep.zip].compact.join(', ')


        addresses_to_destroy.each do |addr|
          begin
            addr.destroy
          rescue StandardError => e
            Rails.logger.error("Failed to destroy address id=#{addr.id} for person hbx_id=#{person.hbx_id}: #{e.message}")
          end
        end

      destroyed_total += addresses_to_destroy.size

      csv << [
        person.hbx_id,
        groups.count { |_, g| g.size > 1 },
        addresses_to_destroy.size,
        kept_str,
        destroyed_addrs.join(' || ')
      ]
    end
  end
end

puts "CSV generated: #{output_path}"