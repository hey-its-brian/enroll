# frozen_string_literal: true

# This task identifies evidences where:
# 1. Evidence is in outstanding state
# 2. Has at least 2 state history records
# 3. Last two consecutive state transitions occurred within 10 seconds
# 4. The from_state remained the same but to_state changed between transitions
#
# This criteria captures evidences impacted by the reconciliation/hub response data race identified in CRM-28028.
#
# Usage:
#   bundle exec rake fix_hub_call_overridden_evidences:fix
#
# Output: Creates a detailed report of impacted families and their evidence

require 'benchmark'
require 'csv'

namespace :fix_hub_call_overridden_evidences do
  desc "Generate impact report for families with rapid evidence state transitions"
  task fix: :environment do
    puts "Starting impact analysis hub call overridden evidences..."
    
    def get_impacted_evidence(applicant)
      applicant.eligibilities.map(&:evidences).flatten.select do |evidence|
        next false unless evidence.outstanding?
        
        states = evidence.state_histories
        next false if states.size < 2

        state_1, state_2 = states.each_cons(2).to_a.last
        
        if state_1.created_at.nil? || state_2.created_at.nil?
          puts "Missing created_at in state histories for evidence #{evidence.id} of applicant #{applicant.id}"
          next false
        end
        
        next false unless (state_1.created_at - state_2.created_at).abs < 10.seconds
        (state_1.from_state == state_2.from_state) && (state_1.to_state != state_2.to_state)
      end
    end

    @results = []
    elapsed = Benchmark.measure do
      families = Family.where(:latest_application_gid.exists => true)
      total = families.count
      
      puts "Found #{total} families to process..."
      
      families.pluck('id').each.with_index(1) do |fam_id, index|
        puts "Processing family #{index} of #{total}" if (index % 1000).zero?
        
        family = Family.find(fam_id)
        application = family.latest_application
        
        # Skip migration applications
        next false if application.origin == :migration
        
        application.applicants.each do |applicant|
          impacted_evidences = get_impacted_evidence(applicant)
          
          impacted_evidences.each do |evidence|
            states = evidence.state_histories
            state_1, state_2 = states.each_cons(2).to_a.last
            
            @results << {
              family_hbx_id: family.primary_applicant.hbx_id,
              application_hbx_id: application.hbx_id,
              applicant_hbx_id: applicant.person.hbx_id,
              evidence_key: evidence.key,
              current_state: evidence.current_state,
              action_1: state_1.event,
              from_state_1: state_1.from_state,
              to_state_1: state_1.to_state,
              action_2: state_2.event,
              from_state_2: state_2.from_state,
              to_state_2: state_2.to_state,
              transition_1_time: state_1.created_at,
              transition_2_time: state_2.created_at,
              time_diff_seconds: (state_1.created_at - state_2.created_at).abs,
              state_histories_count: states.size,
              most_recent_event: evidence.verification_histories.last&.action
            }

            evidence.call_hub(
              {
                action_name: 'hub_request',
                update_reason: "Requested Hub for verification (CRM-28214)",
                updated_by: 'system'
              }
            )
          end
        end
      end
    end

    puts "\nProcessing completed in #{elapsed.real.round(2)} seconds"
    puts "Found #{@results.map { |r| r[:family_hbx_id] }.uniq.size} impacted families"
    puts "Found #{@results.size} impacted evidences"

    # Generate CSV report
    timestamp = Time.current.strftime("%Y_%m_%d_%H_%M")
    csv_filename = Rails.root.join("hub_call_overridden_evidences_report_#{timestamp}.csv")
    
    CSV.open(csv_filename, 'w', write_headers: true, headers: [
      'Family HBX ID',
      'Application HBX ID',
      'Applicant HBX ID',
      'Evidence Key',
      'Current State',
      'Action 1',
      'From State 1',
      'To State 1',
      'Action 2',
      'From State 2',
      'To State 2',
      'Transition 1 Time',
      'Transition 2 Time',
      'Time Difference (seconds)',
      'Total State Histories',
      'Most Recent Event'
    ]) do |csv|
      @results.each do |result|
        csv << [
          result[:family_hbx_id],
          result[:application_hbx_id],
          result[:applicant_hbx_id],
          result[:evidence_key],
          result[:current_state],
          result[:action_1],
          result[:from_state_1],
          result[:to_state_1],
          result[:action_2],
          result[:from_state_2],
          result[:to_state_2],
          result[:transition_1_time],
          result[:transition_2_time],
          result[:time_diff_seconds],
          result[:state_histories_count],
          result[:most_recent_event]
        ]
      end
    end

    puts "Detailed report saved to: #{csv_filename}"
    puts "Processing time: #{elapsed.real.round(2)} seconds"
  end
end