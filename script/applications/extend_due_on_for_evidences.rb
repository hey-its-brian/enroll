# frozen_string_literal: true

# Script: Extend evidence due dates for targeted applications
#
# Overview:
# - Validates CLI arguments and resolves evidence types.
# - For each application, locates applicants that have the requested evidences.
# - Extends due_on for evidences in eligible states only when due_on exists and is not in the future.
# - Recomputes applicant eligibility, persists changes, and rebuilds Family determinations.
# - Emits structured logs to: log/extend_due_date_logger_YYYY_MM_DD.log
#
# Usage:
#   rails runner script/applications/extend_due_on_for_evidences.rb "evidence_type1,evidence_type2|all" EXTENSION_DAYS "app_hbx_id1,app_hbx_id2"
#
# Supported evidence keys:
#   income_evidence, non_esi_mec_evidence, esi_evidence,
#   local_mec_evidence, citizenship_evidence, social_security_number_evidence

EVIDENCE_TYPES = %w[
  income_evidence
  non_esi_mec_evidence
  esi_evidence
  local_mec_evidence
  citizenship_evidence
  social_security_number_evidence
].freeze

ELIGIBILITY_KEY_MAPPING = {
  'income_evidence' => 'aptc_csr_eligibility',
  'non_esi_mec_evidence' => 'aptc_csr_eligibility',
  'esi_evidence' => 'aptc_csr_eligibility',
  'local_mec_evidence' => 'aptc_csr_eligibility',
  'citizenship_evidence' => 'individual_market_eligibility',
  'social_security_number_evidence' => 'individual_market_eligibility'
}.freeze

ELIGIBLE_EVIDENCE_STATES = %w[outstanding rejected review].freeze

def filter_evidence_types(evidences_arg)
  if evidences_arg.split(',').map(&:strip).include?('all')
    EVIDENCE_TYPES
  else
    requested = evidences_arg.split(',').map(&:strip)
    invalid = requested - EVIDENCE_TYPES
    abort_with("Invalid evidence types: #{invalid.join(', ')}") unless invalid.empty?
    requested
  end
end

def parse_arguments
  evidences_arg = ARGV[0]&.strip
  extension_days = ARGV[1].to_i
  application_hbx_ids = ARGV[2]&.split(',')&.map(&:strip)&.reject(&:empty?) || []

  abort_with("Missing evidence types. Provide comma-separated list or 'all'.") if evidences_arg.nil? || evidences_arg.empty?
  abort_with('Extension days must be a positive integer.') if extension_days.nil? || extension_days <= 0
  abort_with('Provide at least one application hbx_id.') if application_hbx_ids.empty?

  evidence_types = filter_evidence_types(evidences_arg)
  [evidence_types, extension_days, application_hbx_ids]
end

def abort_with(message)
  logger.error("Error: #{message}")
  abort
end

def extend_due_date_logger
  @extend_due_date_logger ||= Logger.new(
    "#{Rails.root}/log/extend_due_date_logger_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
  ).tap do |log|
    log.formatter = proc do |severity, datetime, _progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
  end
end

def rebuild_family_determinations!(family_id)
  family = Family.where(id: family_id).first
  result = Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
  if result.success?
    extend_due_date_logger.info("Successfully rebuilt determinations for family id=#{family.id}")
    true
  else
    extend_due_date_logger.error("Failed to rebuild determinations for family id=#{family.id}: #{result.failure}")
    false
  end
end

evidence_types, extension_days, application_hbx_ids = parse_arguments

field_names = %w[
  family_id
  application_hbx_id
  is_renewal?
  application_created_at
  primary_applicant_person_hbx_id
  applicant_person_hbx_id
  evidence_key
  evidence_state
  old_due_on
  new_due_on
  updated_by
  action
  update_reason
  status_message
]

file_name = "#{Rails.root}/extend_evidence_due_dates_report_#{DateTime.now.strftime('%Y_%m_%d_%H_%M_%S')}.csv"

CSV.open(file_name, 'w', force_quotes: true) do |csv|
  csv << field_names
  application_hbx_ids.each do |app_hbx_id|
    application = ::FinancialAssistance::Application.where(hbx_id: app_hbx_id).first
    if application.blank?
      extend_due_date_logger.error("Application not found for hbx_id: #{app_hbx_id}")
      next
    end

    eligibility_keys = evidence_types.collect { |etype| ELIGIBILITY_KEY_MAPPING[etype] }.compact.uniq

    application.applicants.each do |applicant|
      applicant.eligibilities.where(:key.in => eligibility_keys).each do |eligibility|

        eligibility.evidences.where(:key.in => evidence_types).each do |evidence|
          unless ELIGIBLE_EVIDENCE_STATES.include?(evidence.current_state.to_s)
            extend_due_date_logger.info("Skip evidence key=#{evidence.key} state=#{evidence.current_state}")
            csv << [application.family_id, app_hbx_id, application.predecessor_id.present?, application.created_at, application.primary_applicant.person_hbx_id, applicant.person_hbx_id, evidence.key, evidence.current_state,
                    "N/A", "N/A", "", "", "", "Skip evidence key=#{evidence.key} state=#{evidence.current_state}"]
            next
          end
          old_due_on = evidence.due_on
          if old_due_on.blank?
            extend_due_date_logger.info("Skip evidence key=#{evidence.key} due_on=#{old_due_on || 'nil'} (nil or future)")
            vh = evidence.verification_histories.last
            csv << [application.family_id, app_hbx_id, application.predecessor_id.present?, application.created_at, application.primary_applicant.person_hbx_id, applicant.person_hbx_id, evidence.key, evidence.current_state,
                    old_due_on, "N/A", vh&.updated_by, vh&.action, vh&.update_reason, "Skip evidence key=#{evidence.key} due_on=#{old_due_on || 'nil'}"]
            next
          end

          new_date = Date.today + extension_days
          if new_date != old_due_on
            evidence.manually_extend_due_date(new_date, 'Admin')

            extend_due_date_logger.info("Extended evidence key=#{evidence.key} due_on #{old_due_on.strftime('%m/%d/%Y')} -> #{evidence.due_on.strftime('%m/%d/%Y')}")
            vh = evidence.verification_histories.last
            csv << [application.family_id, app_hbx_id, application.predecessor_id.present?, application.created_at, application.primary_applicant.person_hbx_id, applicant.person_hbx_id, evidence.key, evidence.current_state,
                    old_due_on.strftime('%m/%d/%Y'), evidence.due_on.strftime('%m/%d/%Y'), vh&.updated_by, vh&.action, vh&.update_reason, "successfully extended due date"]
          else
            extend_due_date_logger.info("No change for evidence key=#{evidence.key} due_on remains #{evidence.due_on.strftime('%m/%d/%Y')}")
            vh = evidence.verification_histories.last
            csv << [application.family_id, app_hbx_id, application.predecessor_id.present?, application.created_at, application.primary_applicant.person_hbx_id, applicant.person_hbx_id, evidence.key, evidence.current_state,
                    old_due_on.strftime('%m/%d/%Y'), evidence.due_on.strftime('%m/%d/%Y'), vh&.updated_by, vh&.action, vh&.update_reason, "no change in due date"]
          end
        end

        reason = "updated evidence due dates on #{TimeKeeper.date_of_record.strftime('%m/%d/%Y')}"
        eligibility.determine_eligibility_state(reason)
        eligibility.is_satisfied = eligibility.evidences.all?(&:is_satisfied)
      end
    end

    if application.save!
      extend_due_date_logger.info("Processed application hbx_id: #{app_hbx_id}")
      rebuild_family_determinations!(application.family_id)
    else
      extend_due_date_logger.error("Failed to save application hbx_id: #{app_hbx_id}")
    end
  rescue StandardError => e
    extend_due_date_logger.error("Failed to extend due dates for application hbx_id: #{app_hbx_id} due to error: #{e.message}")
  end
end