# frozen_string_literal: true

require 'csv'
require 'logger'
require 'fileutils'

module Operations
  module Eligibilities
    # Background:
    # find all consumers who received a DR notice in given range
    # check the latest application applicants' individual market eligibility
    # extend the due date if the evidence is in rejected or outstanding state
    class ExtendDueDateForImEvidences
      include Dry::Monads[:result, :do]

      DR_NOTICE_SUBJECTS = [
        "Action Needed - Submit Documents",
        "Reminder - You Must Submit Documents",
        "Don't Forget - You Must Submit Documents",
        "Don't Miss the Deadline - You Must Submit Documents",
        "Final Notice - You Must Submit Documents"
      ].freeze

      ELIGIBLE_EVIDENCE_STATES = %i[outstanding rejected].freeze

      def call(params = {})
        start_date, end_date, output_path, extension_days = yield parse_params(params)
        range = start_date.beginning_of_day..end_date.end_of_day

        people = yield find_people(range)

        rows, max_evidences = extend_evidences(people, range, extension_days)

        headers = base_headers
        dynamic_headers = headers + ["applicant_hbx_id"] + (1..max_evidences).flat_map do |j|
          [
            "evidence_key_#{j}",
            "current_evidence_state_#{j}",
            "old_due_on_#{j}",
            "new_due_on_#{j}"
          ]
        end

        path = write_csv(dynamic_headers, rows, max_evidences, output_path)

        Success(output_path: path, rows_count: rows.size)
      end

      private

      def parse_params(params)
        start_date = params[:start_date] ? Date.parse(params[:start_date].to_s) : Date.new(2025, 10, 16)
        end_date = Date.today
        extension_days = (params[:extension_days] || 96).to_i
        timestamp = Time.current.strftime('%Y_%m_%d_%H%M%S')
        output_path = Rails.root.join("dr_consumers_current_outstanding_or_rejected_#{timestamp}.csv").to_s
        Success([start_date, end_date, output_path, extension_days])
      rescue StandardError => e
        Failure("Invalid date params: #{e.message}")
      end

      def find_people(range)
        people = Person.where(:'inbox.messages' => { :$elemMatch => { created_at: range, :subject.in => DR_NOTICE_SUBJECTS } })
        Success(people)
      end

      def extend_due_date_logger
        @extend_due_date_logger ||= begin
          path = Rails.root.join('log', 'extend_due_date_for_im_evidences.log')
          FileUtils.mkdir_p(File.dirname(path))
          logger = Logger.new(path)
          logger.progname = 'ExtendDueDateForImEvidences'
          logger.level = Logger::INFO
          logger
        end
      end

      def extend_evidences(people, range, extension_days)
        rows = []
        max_evidences = 0

        people.each do |person|

          person_rows, person_max, _updated = process_person(person, range, extension_days)
          rows.concat(person_rows)
          max_evidences = [max_evidences, person_max].max
        rescue StandardError => e
          extend_due_date_logger.error("Error processing person hbx_id=#{person&.hbx_id}: #{e.message}")

        end

        [rows, max_evidences]
      end

      def base_headers
        [
          'person_hbx_id',
          'first_notice_subject',
          'first_notice_created_at',
          'current_application_type',
          'current_application_hbx_id',
          'assistance_year'
        ]
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

      def write_csv(headers, rows, max_evidences, output_path)
        CSV.open(output_path, 'w') do |csv|
          csv << headers
          rows.each do |data|
            evs = data[:evidences] + Array.new(max_evidences - data[:evidences].size) do
              { evidence_key: nil, current_evidence_state: nil, old_due_on: nil, new_due_on: nil }
            end
            csv << (data[:base] + evs.flat_map { |e| [e[:evidence_key], e[:current_evidence_state], e[:old_due_on], e[:new_due_on]] })
          end
        end
        output_path
      end

      def process_person(person, range, extension_days)
        rows = []
        max_evidences = 0
        family = person.primary_family
        return [rows, max_evidences, false] unless family.present?

        first_notice = first_dr_notice(person, range)
        return [rows, max_evidences, false] unless first_notice

        return [rows, max_evidences, false] unless has_ivl_enrollments?(family)

        current_application = current_application_for(family)
        return [rows, max_evidences, false] unless current_application.present?

        @person_updated = false

        current_application.applicants.each do |applicant|
          ivl_eligibility = ivl_eligibility_for(applicant)
          next unless ivl_eligibility

          evidences = extend_evidences_for(ivl_eligibility, extension_days)
          next unless evidences.any?

          max_evidences = [max_evidences, evidences.size].max
          rows << build_row(person, first_notice, current_application, applicant_hbx_id_for(applicant), evidences)
        end
        persist_application_and_rebuild(family, current_application) if @person_updated

        [rows, max_evidences, @person_updated]
      end

      def first_dr_notice(person, range)
        person.inbox.messages.where(:created_at => range, :subject.in => DR_NOTICE_SUBJECTS).order_by(created_at: :asc).first
      end

      def has_ivl_enrollments?(family)
        HbxEnrollment.where(:family_id => family.id).individual_market.enrolled_and_renewing.present?
      end

      def current_application_for(family)
        family.latest_application
      end

      def ivl_eligibility_for(applicant)
        applicant.eligibilities.where(title: 'Individual Market Eligibility').first
      end

      def extend_evidences_for(ivl_eligibility, extension_days)
        evidences = []
        ivl_eligibility.evidences.each do |evidence|
          next unless evidence.due_on.present? && ELIGIBLE_EVIDENCE_STATES.include?(evidence.current_state.to_sym)
          @person_updated = true
          old_due_on = evidence.due_on
          new_due_on = TimeKeeper.date_of_record + extension_days
          evidence.manually_extend_due_date(new_due_on, 'Admin')

          evidences << {
            evidence_key: evidence.key,
            current_evidence_state: evidence.current_state,
            old_due_on: old_due_on,
            new_due_on: new_due_on
          }
        end
        evidences
      end

      def build_row(person, first_notice, current_application, applicant_hbx_id, evidences)
        {
          base: [
            person.hbx_id,
            first_notice.subject,
            first_notice.created_at,
            (current_application.instance_of?(::FinancialAssistance::Application) ? 'FAA' : 'QHP'),
            (current_application.respond_to?(:hbx_id) ? current_application.hbx_id : current_application.id.to_s),
            current_application.assistance_year,
            applicant_hbx_id
          ],
          evidences: evidences
        }
      end

      def applicant_hbx_id_for(applicant)
        if applicant.respond_to?(:person_hbx_id)
          applicant.person_hbx_id
        elsif applicant.respond_to?(:person) && applicant.person.respond_to?(:hbx_id)
          applicant.person.hbx_id
        elsif applicant.respond_to?(:hbx_id)
          applicant.hbx_id
        end
      end

      def persist_application_and_rebuild(family, current_application)
        if current_application.save!
          rebuild_family_determinations!(family.id)
        else
          extend_due_date_logger.error("Failed to save application for family id=#{family.id}: #{current_application.errors.full_messages.join(', ')}")
        end
      end
    end
  end
end


