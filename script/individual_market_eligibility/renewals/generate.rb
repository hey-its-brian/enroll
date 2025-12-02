# frozen_string_literal: true

#------------------------------------------------------------------------------
# Script::IndividualMarketEligibility::Renewals::Generate
#
# Creates QHP (Individual Market) eligibility renewal applications for families
# for a specified renewal year, based on HBX IDs provided via ARGV.
#
# SCOPE:
#   - Namespaced to prevent class collisions when multiple scripts are loaded.
#   - Focused on QHP/IVL eligibility renewals only (not FA determination).
#
# RESPONSIBILITIES:
#   1. Parse CLI arguments (ARGV) to obtain:
#        - Renewal year (ARGV[0]) as Integer.
#        - Comma-separated HBX IDs list (ARGV[1]).
#   2. Validate constraints:
#        - Renewal year must not be in the past.
#        - Execution must occur on/before OE cutoff (Jan 15 of renewal year).
#        - At least one HBX ID must be provided.
#   3. For each HBX ID:
#        - Fetch Person and their primary Family.
#        - Validate eligibility for IVL renewal:
#            • Family has at least one current-year enrolled enrollment.
#            • No non-initial QHP application exists for the renewal year.
#            • Eligible if latest application type is 'qhp'; otherwise,
#              FA applications for the renewal year must exist and all be in:
#                - 'applicants_update_required' OR
#                - 'income_verification_extension_required'.
#        - Create a QHP renewal draft application (no FA evidence building).
#   4. Structured logging:
#        - Per HBX ID START/END markers.
#        - INFO for progress, ERROR for failures.
#
# USAGE (Rails runner):
#   rails r script/individual_market_eligibility/renewals/generate.rb 2026 100095,200123
#
# ARGUMENTS (ARGV):
#   @param ARGV[0] [Integer] renewal_year Target assistance year.
#   @param ARGV[1] [String]  Comma-separated HBX IDs (primary persons).
#
# CONSTRAINTS / SAFEGUARDS:
#   - Stops if Date.today > Date.new(renewal_year, 1, 15) (OE cutoff).
#   - Skips families already having non-initial QHP applications for the year.
#   - Continues processing other HBX IDs on per-person errors.
#
# LOGGING:
#   - Outputs to log/qhp_renewal_generated_<timestamp>.log
#   - Messages prefixed with "QHP:" for quick filtering.
#
# ERROR HANDLING:
#   - Per-person errors rescued and logged (processing continues).
#   - Top-level unexpected errors logged; exits with non-zero status.
#
# MAINTENANCE NOTES:
#   - Use for CIR-related tasks and defect fixes only.
#   - Review by a project developer required for workflow changes.
#
# @example Run for two HBX IDs for year 2026
#   rails r script/individual_market_eligibility/renewals/generate.rb 2026 100095,200123
#
# @example Log excerpt
#   QHP: ---- HBX ID 100095 ---- START
#   QHP: Processing renewal for Primary Person HBX ID: 100095
#   QHP: Created QHP renewal Application ID: 5f9c...
#   QHP: ---- HBX ID 100095 ---- END
#
# @version 1.0
#------------------------------------------------------------------------------
require 'logger'

renewal_year_arg    = ARGV[0]&.to_i if ARGV[0]
primary_hbx_ids_arg = (ARGV[1].to_s.split(',') || []).map(&:strip).reject(&:empty?).uniq

module Script
  module IndividualMarketEligibility
    module Renewals
      class Generate
        def initialize(renewal_year:, primary_person_hbx_ids:)
          @renewal_year           = renewal_year
          @primary_person_hbx_ids = primary_person_hbx_ids
          @qhp_logger = Logger.new("#{Rails.root}/log/qhp_renewal_generated_#{Time.now.strftime('%Y_%m_%d %H_%M_%S')}.log")
        end

        def process
          return log_failure('QHP: Renewal year missing') unless renewal_year
          return log_failure("QHP: Renewal period cannot be post OE 1/15/#{renewal_year}") if Date.today > Date.new(renewal_year, 1, 15)
          return log_failure('QHP: Renewal year cannot be in the past') if Date.today.year > renewal_year
          return log_failure('QHP: Primary person hbx_ids missing') if primary_person_hbx_ids.blank?

          log "QHP: Starting renewal creation for year #{renewal_year}. Count=#{primary_person_hbx_ids.size}"
          primary_person_hbx_ids.each { |hbx_id| process_person(hbx_id) }
          log 'QHP: Finished renewal creation run'
        rescue StandardError => e
          log_failure "QHP: Unhandled error in run: #{e.class}: #{e.message}"
          exit(1)
        end

        private

        attr_reader :renewal_year, :primary_person_hbx_ids, :qhp_logger

        def process_person(hbx_id)
          log_section(hbx_id) { run_flow(hbx_id) }
        rescue StandardError => e
          log_failure "QHP: Unhandled error for HBX ID #{hbx_id}: #{e.class}: #{e.message}"
        end

        def run_flow(hbx_id)
          log "QHP: Processing renewal for Primary Person HBX ID: #{hbx_id}"
          person = Person.where(hbx_id: hbx_id).first
          return log_failure 'QHP: No person found' unless person

          family = person.primary_family
          return log_failure 'QHP: No family found for person' unless family

          unless eligible_for_ivl_eligibility_renewal(family, renewal_year)
            return log_failure "QHP: Family ID #{family.id} not eligible for IVL eligibility renewal #{renewal_year}. Skipping."
          end

          build_renewal_application(family, hbx_id)
        end

        def eligible_for_ivl_eligibility_renewal(family, year)
          active_enrollments = family.hbx_enrollments.enrolled.current_year
          return false if active_enrollments.empty?

          renewal_qhp_apps = family.qhp_applications_for_year(year)
          return false if renewal_qhp_apps.any? { |app| !app.is_initial? }

          return true if family.latest_application_type == 'qhp'

          fa_apps = ::FinancialAssistance::Application.only(:assistance_year, :family_id, :aasm_state)
                       .where(assistance_year: year, family_id: family.id)
          return false if fa_apps.empty?

          fa_apps.all? { |app| %w[applicants_update_required income_verification_extension_required].include?(app.aasm_state) }
        end

        def build_renewal_application(family, hbx_id)
          result = Operations::IndividualMarket::Applications::Renewals::Create.new.call(
            family_id: family.id,
            renewal_year: renewal_year
          )
          if result.failure?
            log_failure "QHP: Failed to create QHP renewal for HBX ID #{hbx_id}: #{result.failure}"
            return nil
          end
          renewal_app = result.success
          log "QHP: Created QHP renewal Application ID: #{renewal_app.id}"
          renewal_app
        end

        def log(msg)        = qhp_logger.info(msg)
        def log_failure(msg)= qhp_logger.error(msg)

        def log_section(hbx_id)
          log "QHP: ---- HBX ID #{hbx_id} ---- START"
          yield
        ensure
          log "QHP: ---- HBX ID #{hbx_id} ---- END"
        end
      end
    end
  end
end

if Rails.env.test? || (defined?(Rails) && $PROGRAM_NAME.include?('rails'))
  Script::IndividualMarketEligibility::Renewals::Generate
    .new(renewal_year: renewal_year_arg, primary_person_hbx_ids: primary_hbx_ids_arg)
    .process
end