# frozen_string_literal: true

require File.join(Rails.root, 'app', 'data_migrations', 'fix_atp_outbound_verification_codes')
# This migration is to resend account transfers that have failed due to missing verification codes

# RAILS_ENV=production bundle exec rake migrations:fix_atp_outbound_verification_codes text_file='path/to/hbx_ids.txt'
namespace :migrations do
  desc 'resending account transfers that have failed due to missing verification codes'
  FixAtpOutboundVerificationCodes.define_task :fix_atp_outbound_verification_codes => :environment
end
