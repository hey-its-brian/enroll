# frozen_string_literal: true

require File.join(Rails.root, "lib/mongoid_migration_task")

# This datafix resends account transfers that have failed due to missing verification codes in Medicaid Gateway
# To run this, pass a path to a text file containing HBX IDs in array format:
# FixAtpOutboundVerificationCodes.new.migrate('path/to/hbx_ids.txt')
# or using the rake action:
# RAILS_ENV=production bundle exec rake migrations:fix_atp_outbound_verification_codes text_file='path/to/hbx_ids.txt'
# The text file should contain IDs in this format: ['id1', 'id2', 'id3']
class FixAtpOutboundVerificationCodes < MongoidMigrationTask
  def parse_array_format(content)
    # Validate the format matches either ['id1', 'id2'] or ["id1", "id2"] pattern with optional whitespace
    raise ArgumentError, "No valid HBX IDs found in the input file. Format should be: ['id1', 'id2'] or [\"id1\", \"id2\"]" unless content.match?(/\A\s*\[(\s*['"][^'"]*?['"]\s*(?:,\s*['"][^'"]*?['"]\s*)*)\]\s*\z/)

    # Remove brackets and split by commas
    content.gsub(/[\[\]]/, '').split(',').map do |id|
      # Remove quotes (both single and double) and whitespace
      id.gsub(/['"]/, '').strip
    end.reject(&:empty?)
  end

  def migrate(text_file = nil)
    text_file ||= ENV['text_file']
    raise ArgumentError, "Input must be a path to an existing text file containing HBX IDs in array format: ['id1', 'id2', 'id3']" unless text_file.is_a?(String) && File.exist?(text_file)

    content = File.read(text_file).strip
    hbx_ids = parse_array_format(content)

    raise ArgumentError, "No valid HBX IDs found in the input file. Format should be: ['id1', 'id2', 'id3']" if hbx_ids.empty?

    transfer_failures = []
    begin
      hbx_ids.each do |id|
        application = FinancialAssistance::Application.find_by(hbx_id: id)
        transfer_failures << id if application && !application.transfer_account.success?
      end
    rescue StandardError => e
      puts "Error: #{e}"
    end

    if transfer_failures.empty?
      puts "Successfully resubmitted all applications"
    else
      puts "Partial resubmission of applications completed. Application IDs of repeat failures: #{transfer_failures}"
    end
  end
end