# frozen_string_literal: true

require File.join(Rails.root, "lib/mongoid_migration_task")
require 'csv'
require "#{Rails.root}/app/helpers/l10n_helper.rb"

# List of people with any verification_type or evidence in rejected status
class RejectedVerificationTypesOrEvidencesReport < MongoidMigrationTask
  include L10nHelper

  def assistance_year
    TimeKeeper.date_of_record.year
  end

  def application_family_ids
    faa_family_ids = FinancialAssistance::Application.by_year(assistance_year)
                                                     .submitted_and_after
                                                     .where(
                                                       :"applicants.eligibilities.evidences.current_state" => :rejected
                                                     ).distinct(:family_id)

    ima_family_ids = IndividualMarket::Application.from_year(assistance_year)
                                                  .submitted_and_after
                                                  .where(
                                                    :"applicants.eligibilities.evidences.current_state" => :rejected
                                                  ).distinct(:family_id)

    faa_family_ids.concat(ima_family_ids).uniq
  end

  def families
    @families ||= Family.where(:id.in => application_family_ids)
  end

  def display_evidence_type_name(evidence)
    evidence_aliases = {
      'esi_mec_evidence' => l10n('faa.evidence_type_esi'),
      'non_esi_mec_evidence' => l10n('faa.evidence_type_non_esi'),
      'local_mec_evidence' => l10n('faa.evidence_type_aces')
    }

    evidence_aliases.keys.include?(evidence.key) ? evidence_aliases[evidence.key] : evidence.title.gsub(/ Evidence$/, '')
  end

  def data_for_rejected_evidence(evidence, primary, application, active_enr, person)
    latest_sh = evidence.state_histories.order(created_at: :desc).first
    evidence_name = display_evidence_type_name(evidence)
    [primary.hbx_id,
     primary.first_name,
     primary.last_name,
     primary.consumer_role&.contact_method,
     primary.home_phone&.full_phone_number,
     primary.work_email_or_best,
     application&.hbx_id,
     person.hbx_id,
     evidence_name,
     evidence.current_state.to_s,
     latest_sh&.transition_at&.in_time_zone('Eastern Time (US & Canada)'),
     active_enr.present? ? 'Yes' : 'No']
  end

  def field_names
    %w[PrimaryHBXID FirstName LastName CommunicationPreference HomePhoneNumber
       PrimaryEmailAddress ApplicationID MemberHBXID MemberEvidenceType
       CurrentVerificationStatus LastStatusTransition ActiveEnrollment]
  end

  def process_application(application, primary, csv, active_enr, family)
    application.applicants.each do |applicant|
      person = family.active_family_members.flat_map(&:person).detect { |per| per.hbx_id == applicant.person.hbx_id }
      next applicant unless person.present?

      evidences = applicant.eligibilities.flat_map(&:evidences)

      evidences.each do |evidence|
        csv << data_for_rejected_evidence(evidence, primary, application, active_enr, person) if evidence.current_state == :rejected
      end
    end
  end

  def process_families(families_per_iteration, offset_count, csv)
    families.no_timeout.limit(families_per_iteration).offset(offset_count).inject([]) do |_dummy, family|
      primary = family.primary_person
      application = family.latest_application
      active_enr = family.hbx_enrollments.by_year(assistance_year).enrolled_and_renewal.order(created_at: :desc).first

      process_application(application, primary, csv, active_enr, family) if application.present?
    rescue StandardError => e
      puts "Unable to process person with hbx_id: #{primary&.hbx_id}, message: #{e.message}, backtrace: #{e.backtrace}" unless Rails.env.test?
    end
  end

  def migrate
    file_name = "#{Rails.root}/rejected_verification_types_or_evidences_report.csv"
    start_time = Time.current

    puts "*********** STARTING Rejected Verification Types or Evidences Report ******************" unless Rails.env.test?
    puts "Report started at: #{start_time.in_time_zone('Eastern Time (US & Canada)')}" unless Rails.env.test?

    CSV.open(file_name, 'w', force_quotes: true) do |csv|
      csv << field_names
      total_count = families.count
      puts "Total number of families: #{total_count}" unless Rails.env.test?
      families_per_iteration = 1_000.0
      number_of_iterations = (total_count / families_per_iteration).ceil
      counter = 0

      while counter < number_of_iterations
        puts "Processing #{counter.next.ordinalize} 1000 families." unless Rails.env.test?
        offset_count = families_per_iteration * counter
        process_families(families_per_iteration, offset_count, csv)
        counter += 1
      end
    end

    end_time = Time.current
    duration = end_time - start_time

    puts "Report completed at: #{end_time.in_time_zone('Eastern Time (US & Canada)')}" unless Rails.env.test?
    puts "Total time taken: #{duration.round(2)} seconds (#{(duration / 60.0).round(2)} minutes)" unless Rails.env.test?
    puts "*********** DONE ******************" unless Rails.env.test?
  end
end