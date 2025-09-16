# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module HbxAdmin
    module DryRun
      module Individual
        # Operation to fetch notices efficiently
        class Notices
          include Dry::Monads[:result, :do]

          # NOTICE_TITLE_MAPPING is only used for redetermination UI purpose. Do not use this CONSTANT outside this class. DB and Notices has different values.
          NOTICE_TITLE_MAPPING = {
            "Open Enrollment - Medicaid" => "OEM",
            "Open Enrollment - Tax Credit" => "OEA",
            "Open Enrollment - Marketplace Insurance" => "OEU",
            "Your Eligibility Results - Health Coverage Eligibility" => "OEQ",
            "Your Eligibility Results Consent or Missing Information Needed" => "OEG"
          }.freeze

          # @return [Dry::Monads::Result]
          def call
            coverage_years = yield fetch_coverage_years
            year = coverage_years[0]
            notices = yield fetch_notices(year)

            Success(notices)
          end

          private

          def fetch_coverage_years
            benefits_result = ::Operations::HbxAdmin::DryRun::Individual::Benefits.new.call
            return Failure("Failed to get coverage years") if benefits_result.failure?

            _, coverage_years = benefits_result.value!
            Success(coverage_years)
          rescue StandardError => e
            Failure("Coverage years error: #{e.message}")
          end

          def fetch_notices(year)
            start_date = Date.new(year, 1, 1) - 6.months
            end_date = Date.new(year, 1, 1)

            notice_title_mapping = NOTICE_TITLE_MAPPING

            pipeline_result = ::Operations::HbxAdmin::DryRun::NoticeQuery.new.call(
              start_date: start_date,
              end_date: end_date,
              title_codes: notice_title_mapping.keys
            )

            return Success(notice_title_mapping.values.map { |code| [code, 0] }.to_h) if pipeline_result.failure?

            # Execute the pipeline on Person collection
            notices_raw = Person.collection.aggregate(
              pipeline_result.value!,
              allow_disk_use: true,
              batch_size: 500,
              max_time_ms: 30_000
            ).to_a

            # Build result hash efficiently with codes as keys
            oe_determined_notices = notice_title_mapping.values.map { |code| [code, 0] }.to_h

            notices_raw.each do |notice|
              code = notice_title_mapping[notice["title"]]
              oe_determined_notices[code] = notice["count"] if code
            end

            Success(oe_determined_notices)
          rescue StandardError
            # Return default structure on error with codes as keys
            Success(NOTICE_TITLE_MAPPING.values.map { |code| [code, 0] }.to_h)
          end
        end
      end
    end
  end
end
