# frozen_string_literal: true

# This task identifies evidences where:
# 1. Evidence is in outstanding or rejected state
# 2. Has at least 2 state history records
# 3. State transitions occurred within 10 seconds with same from_state but different to_state
#
# For OUTSTANDING status:
#   - Checks last two consecutive state transitions
#
# For REJECTED status:
#   - Checks first two consecutive state transitions after application_determination
#
# This criteria captures evidences impacted by the reconciliation/hub response data race identified in CRM-28028.
#
# Usage:
#   # Generate report only (no hub calls - default):
#   bundle exec rake fix_hub_call_overridden_evidences:fix
#   bundle exec rake fix_hub_call_overridden_evidences:fix[outstanding]
#   bundle exec rake fix_hub_call_overridden_evidences:fix[outstanding,report]
#
#   # Process outstanding status and call hub:
#   bundle exec rake fix_hub_call_overridden_evidences:fix[outstanding,fix]
#
#   # Process rejected status evidences (report only):
#   bundle exec rake fix_hub_call_overridden_evidences:fix[rejected]
#   bundle exec rake fix_hub_call_overridden_evidences:fix[rejected,report]
#
#   # Process rejected status and call hub:
#   bundle exec rake fix_hub_call_overridden_evidences:fix[rejected,fix]
#
#   # Process specific families only (comma-separated Family IDs):
#   FAMILY_IDS="6957ade255d0cf0001996286,6957ade255d0cf0001996287" bundle exec rake fix_hub_call_overridden_evidences:fix[rejected,report]
#
# Output: Creates a detailed report of impacted families and their evidence

require 'benchmark'
require 'csv'

namespace :fix_hub_call_overridden_evidences do
  desc "Generate impact report for families with rapid evidence state transitions"
  task :fix, [:status_type, :mode] => :environment do |_t, args|
    status_type = args[:status_type] || 'outstanding'
    mode = args[:mode] || 'report'
    family_ids = ENV['FAMILY_IDS']&.split(',')&.map(&:strip)&.reject(&:blank?)&.uniq

    call_hub = (mode == 'fix')

    puts "Starting impact analysis hub call overridden evidences..."
    puts "Processing status type: #{status_type.upcase}"
    puts "Mode: #{call_hub ? 'FIX - Calling hub and rebuilding determinations' : 'REPORT - No hub calls, report only'}"
    puts "Filtering by family HBX IDs: #{family_ids.join(', ')}" if family_ids.present?

    # Get impacted evidences for OUTSTANDING status
    # Uses last two consecutive state transitions
    def get_impacted_outstanding_evidence(applicant)
      applicant.eligibilities.map(&:evidences).flatten.select do |evidence|
        validate_outstanding_evidence_criteria(evidence, applicant)
      end
    end

    def validate_outstanding_evidence_criteria(evidence, applicant)
      return false unless evidence.outstanding?

      states = evidence.state_histories.sort_by { |s| s.created_at || Time.current }
      return false if states.size < 2

      state_1, state_2 = states.each_cons(2).to_a.last

      return false unless valid_timestamps?(state_1, state_2, evidence, applicant)
      return false unless rapid_transition?(state_1, state_2)

      race_condition?(state_1, state_2)
    end

    # Get impacted evidences for REJECTED status
    # Uses first two consecutive state transitions AFTER application_determination
    def get_impacted_rejected_evidence(applicant)
      applicant.eligibilities.map(&:evidences).flatten.select do |evidence|
        validate_rejected_evidence_criteria(evidence, applicant)
      end
    end

    def validate_rejected_evidence_criteria(evidence, applicant)
      return false unless evidence.rejected?

      states = evidence.state_histories.sort_by { |s| s.created_at || Time.current }
      return false if states.size < 2

      app_determination_index = states.find_index { |s| s.comment == 'application_determination' }
      return false if app_determination_index.nil?
      return false if states.size <= app_determination_index + 2

      state_1 = states[app_determination_index + 1]
      state_2 = states[app_determination_index + 2]

      return false unless valid_timestamps?(state_1, state_2, evidence, applicant)
      return false unless rapid_transition?(state_1, state_2)

      race_condition?(state_1, state_2)
    end

    def valid_timestamps?(state_1, state_2, evidence, applicant)
      if state_1.created_at.nil? || state_2.created_at.nil?
        puts "Missing created_at in state histories for evidence #{evidence.id} of applicant #{applicant.id}"
        return false
      end
      true
    end

    def rapid_transition?(state_1, state_2)
      (state_1.created_at - state_2.created_at).abs < 10.seconds
    end

    def race_condition?(state_1, state_2)
      (state_1.from_state == state_2.from_state) && (state_1.to_state != state_2.to_state)
    end

    # Get rejection info for an evidence
    # Finds both first and last rejection transitions
    def get_rejection_info(evidence)
      all_rejections = evidence.state_histories
                               .select { |s| s.to_state == :rejected || s.to_state == 'rejected' }
                               .sort_by { |s| s.created_at || Time.current }

      if all_rejections.any?
        first_rejection = all_rejections.first
        last_rejection = all_rejections.last

        {
          first_rejected_at: first_rejection.created_at,
          last_rejected_at: last_rejection.created_at,
          rejected_from: last_rejection.from_state
        }
      else
        {
          first_rejected_at: nil,
          last_rejected_at: nil,
          rejected_from: nil
        }
      end
    end

    @results = []
    elapsed = Benchmark.measure do
      if family_ids.present?
        families = Family.where(:id.in => family_ids)
      else
        families = Family.where(:latest_application_gid.exists => true)
      end

      total = families.count

      puts "Found #{total} families to process..."

      family_id_list = families.pluck('id')
      family_id_list.each.with_index(1) do |fam_id, index|
        impacted = false
        puts "Processing family #{index} of #{total}" if (index % 1000).zero?

        family = Family.find(fam_id)
        application = family.latest_application

        # Skip migration applications
        next false if application.origin == :migration

        application.applicants.each do |applicant|
          # Get impacted evidences based on status_type
          impacted_evidences = if status_type == 'outstanding'
                                 get_impacted_outstanding_evidence(applicant)
                               else
                                 get_impacted_rejected_evidence(applicant)
                               end

          impacted_evidences.each do |evidence|
            impacted = true
            states = evidence.state_histories.sort_by { |s| s.created_at || Time.current }

            # For rejected status, get states after application_determination
            # For outstanding status, get last two consecutive states
            if evidence.rejected?
              app_determination_index = states.find_index { |s| s.comment == 'application_determination' }

              # if app_determination not found, skip this evidence
              if app_determination_index.nil? || states.size <= app_determination_index + 2
                puts "Warning: Expected application_determination not found for evidence #{evidence.id}"
                next
              end

              state_1 = states[app_determination_index + 1]
              state_2 = states[app_determination_index + 2]
            else
              state_1, state_2 = states.each_cons(2).to_a.last
            end

            result_hash = {
              family_id: fam_id.to_s,
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

            # Add rejection info for rejected evidences
            if evidence.rejected?
              rejection_info = get_rejection_info(evidence)
              result_hash[:first_rejected_at] = rejection_info[:first_rejected_at]
              result_hash[:last_rejected_at] = rejection_info[:last_rejected_at]
              result_hash[:rejected_from_state] = rejection_info[:rejected_from]
            end

            @results << result_hash

            next unless call_hub
            evidence.call_hub(
              {
                action_name: 'hub_request',
                update_reason: "Requested Hub for verification (CRM-28214)",
                updated_by: 'system'
              }
            )
          end
        end

        if call_hub && impacted
          family.reset_latest_application
          Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
        end
      end
    end

    puts "\nProcessing completed in #{elapsed.real.round(2)} seconds"
    puts "Found #{@results.map { |r| r[:family_hbx_id] }.uniq.size} impacted families"
    puts "Found #{@results.size} impacted evidences"

    if call_hub
      puts "\nHub called for #{@results.size} evidences"
      puts "Family determinations rebuilt for #{@results.map { |r| r[:family_hbx_id] }.uniq.size} families"
    else
      puts "\nReport generated only. No hub calls made."
      puts "To call hub and rebuild determinations, run with mode=fix:"
      puts "rake fix_hub_call_overridden_evidences:fix[#{status_type},fix]"
    end

    # Generate CSV report
    timestamp = Time.current.strftime("%Y_%m_%d_%H_%M")
    csv_filename = Rails.root.join("hub_call_overridden_evidences_#{status_type}_#{mode}_#{timestamp}.csv")

    # Build headers based on whether we're processing rejected status
    headers = [
      'Family ID',
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
    ]

    # Add rejected-specific columns if processing rejected status
    headers += ['First Rejected At', 'Last Rejected At', 'Rejected From State'] if status_type == 'rejected'

    CSV.open(csv_filename, 'w', write_headers: true, headers: headers) do |csv|
      @results.each do |result|
        row = [
          result[:family_id],
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

        # Add rejected-specific data if processing rejected status
        row += [result[:first_rejected_at], result[:last_rejected_at], result[:rejected_from_state]] if status_type == 'rejected'

        csv << row
      end
    end

    puts "Detailed report saved to: #{csv_filename}"
    puts "Processing time: #{elapsed.real.round(2)} seconds"
  end
end
