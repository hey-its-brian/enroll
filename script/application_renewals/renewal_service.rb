# frozen_string_literal: true

#------------------------------------------------------------------------------
# RenewalService
#
# Executes manual renewal workflow for financial assistance applications
# given a target renewal year and a list of primary person HBX IDs.
#
# RESPONSIBILITIES:
#   1. Validate CLI arguments (renewal year, HBX IDs).
#   2. For each HBX ID:
#        - Locate Person and primary Family.
#        - Skip if a renewal application already exists for the year.
#        - Invoke renewal draft creation operation.
#        - Submit determination request for the created draft.
#   3. Structured START/END logging per HBX ID; error logging on failures.
#
# USAGE (Rails runner):
#   rails r script/application_renewals/renewal_service.rb 2025 12345,67890
#
# ARGUMENTS (ARGV):
#   ARGV[0] Integer renewal year (must be > current year).
#   ARGV[1] Comma-separated HBX IDs of primary persons.
#
# CONSTRAINTS / SAFEGUARDS:
#   - Will not run if renewal year is current or in the past.
#   - Requires at least one valid HBX ID.
#   - Skips families already possessing a FA or QHP renewal application for year.
#
# LOGGING:
#   Writes to log/renewal_service_<timestamp>.log
#   Each HBX ID wrapped with START/END markers for traceability.
#
# ERROR HANDLING:
#   - Per-person errors rescued and logged; processing continues.
#   - Top-level unexpected error logs and exits with non-zero status.
#
# MAINTENANCE NOTES:
#   - Changes restricted to CIR-related requirements or defect fixes.
#   - Review by a project developer required before modifying workflow logic.
#
# @example Run for two HBX IDs and upcoming year
#   rails r script/application_renewals/renewal_service.rb 2026 100095,200123
#
# @example Log excerpt
#   ---- HBX ID 100095 ---- START
#   Processing renewal for Primary Person HBX ID: 100095
#   Created renewal draft Application ID: 5f9c...
#   Successfully determined Application ID: 5f9c...
#   ---- HBX ID 100095 ---- END
#
# @version 1.0
#------------------------------------------------------------------------------
require 'logger'

renewal_year           = ARGV[0]&.to_i if ARGV[0]
primary_person_hbx_ids = (ARGV[1].to_s.split(',') || []).map(&:strip).reject(&:empty?).uniq

# Service object renewal creation and determination.
class RenewalService
  # @!attribute [r] renewal_year
  #   @return [Integer] Target assistance year for renewals.
  # @!attribute [r] primary_person_hbx_ids
  #   @return [Array<String>] HBX IDs of primary persons to process.
  # @!attribute [r] logger
  #   @return [Logger] Dedicated script logger instance.
  def initialize(renewal_year:, primary_person_hbx_ids:)
    @renewal_year              = renewal_year
    @primary_person_hbx_ids    = primary_person_hbx_ids
    @logger = Logger.new("#{Rails.root}/log/renewal_service_#{Time.now.strftime('%Y_%m_%d_%H_%M_%S')}.log")
  end

  # Main entry point.
  #
  # Validates arguments, iterates HBX IDs, delegates to per-person flow.
  # @return [void]
  # @raise [SystemExit] Exits with status 1 on unrecoverable top-level error.
  def process
    return log_failure('Renewal year missing') unless renewal_year
    return log_failure("Renewal period cannot be post OE 1/15/#{renewal_year}") if Date.today > Date.new(renewal_year, 1, 15)
    return log_failure('Renewal year cannot be in the past') if Date.today.year > renewal_year
    return log_failure('Primary person hbx_ids missing') if primary_person_hbx_ids.blank?

    log "Starting renewal creation for year #{renewal_year}. Count=#{primary_person_hbx_ids.size}"

    primary_person_hbx_ids.each { |hbx_id| process_person(hbx_id) }

    log 'Finished renewal creation run'
  rescue StandardError => e
    log_failure "Unhandled error in run: #{e.class}: #{e.message}"
    exit(1)
  end

  private

  attr_reader :renewal_year, :primary_person_hbx_ids, :logger

  # Wraps per-person logic with logging and independent error rescue.
  # @param primary_person_hbx_id [String]
  # @return [void]
  def process_person(primary_person_hbx_id)
    log_section(primary_person_hbx_id) { run_flow(primary_person_hbx_id) }
  rescue StandardError => e
    log_failure "Unhandled error for HBX ID #{primary_person_hbx_id}: #{e.class}: #{e.message}"
  end

  # Executes domain-specific renewal steps for a single HBX ID.
  # @param hbx_id [String]
  # @return [void]
  def run_flow(hbx_id)
    log "Processing renewal for Primary Person HBX ID: #{hbx_id}"

    person = Person.where(hbx_id: hbx_id).first
    return log_failure 'No person found' unless person

    family = person.primary_family
    return log_failure 'No family found for person' unless family

    if existing_applications?(family)
      return log_failure "Family ID #{family.id} has existing FA/QHP renewal application for #{renewal_year}. Skipping."
    end

    renewal_application = build_renewal_application(family, hbx_id)
    return unless renewal_application

    determine_renewal(renewal_application, hbx_id)
  end

  # Checks for pre-existing renewal-related applications.
  # @param family [Family]
  # @return [Boolean] true if a renewal application already exists.
  def existing_applications?(family)
    FinancialAssistance::Application.by_year(renewal_year).where(family_id: family.id).exists? ||
      IndividualMarket::Application.where(assistance_year: renewal_year, family_id: family.id).exists?
  end

  # Builds a renewal draft application via operation.
  # @param family [Family]
  # @param hbx_id [String]
  # @return [FinancialAssistance::Application, nil]
  def build_renewal_application(family, hbx_id)
    result = ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::Renew.new.call(
      family_id: family.id,
      renewal_year: renewal_year
    )
    if result.failure?
      log_failure "Failed to create renewal draft for HBX ID #{hbx_id}: #{result.failure}"
      return nil
    end
    renewal_app = result.success
    log "Created renewal draft Application ID: #{renewal_app.id}"
    renewal_app
  end

  # Submits determination request for previously created renewal application.
  # @param renewal_application [FinancialAssistance::Application]
  # @param hbx_id [String]
  # @return [void]
  def determine_renewal(renewal_application, hbx_id)
    result = ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::SubmitDeterminationRequest.new.call(
      application_id: renewal_application.id
    )
    if result.failure?
      log_failure "Failed to determine renewal application for HBX ID #{hbx_id}: #{result.failure}"
      return
    end
    log "Successfully determined Application ID: #{renewal_application.id}"
  end

  # INFO-level log wrapper.
  # @param msg [String]
  # @return [void]
  def log(msg) = logger.info(msg)

  # ERROR-level log wrapper.
  # @param msg [String]
  # @return [void]
  def log_failure(msg) = logger.error(msg)

  # Structured per-person logging boundary.
  # @param hbx_id [String]
  # @yield Executes the per-person flow.
  # @return [void]
  def log_section(hbx_id)
    log "---- HBX ID #{hbx_id} ---- START"
    yield
  ensure
    log "---- HBX ID #{hbx_id} ---- END"
  end
end

# Entry point invocation.
# Instantiates service and runs process pipeline.
RenewalService.new(renewal_year: renewal_year, primary_person_hbx_ids: primary_person_hbx_ids).process