# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Exports
      module Families
        module Eligibility
          # Exports family eligibility data from a message queue to a CSV file
          #
          # This operation consumes messages from the migration results queue that contain
          # family eligibility data and writes them to a CSV file. Each message contains
          # information about a family's previous and current eligibility determination status.
          class ExportFamilyEligibilityCsv < ::Operations::AsyncMigrations::Exports::BaseQueueCsvExport
            def self.result_queue_name
              "on_enroll.enroll.migration_results"
            end

            def build
              CSV.open(".csv", "wb") do |csv|
                csv << [
                  'Person HBX ID', 'Family Hbx ID', 'Previous Determination Status', 'Previous Due Date', 'Current Determination Status', 'Current Due Date',  'Message'
                ]
              end

              csv_f = CSV.open("redetermine_outstanding_families_eligibilities_report.csv", "ab")
              run_records(csv_f)
              csv_f.close
            end

            def run_records(csv)
              count = 0
              di, _props, payload = @queue.pop(manual_ack: true)
              while di
                count += 1
                puts "Processing record #{count}" if count % 1000 == 0
                data_payload = JSON.parse(payload, symbolize_names: true)
                csv << extract_data_row(data_payload)
                di, _props, payload = @queue.pop(manual_ack: true)
              end
            end

            private

            # Extracts data from the payload into a row for CSV
            #
            # @param data_payload [Hash] The message payload data
            # @return [Array] The extracted data row
            def extract_data_row(data_payload)
              [
                data_payload[:person_hbx_id],
                data_payload[:family_hbx_id],
                data_payload[:previous_determination_status],
                data_payload[:previous_due_date],
                data_payload[:current_determination_status],
                data_payload[:current_due_date],
                data_payload[:message]
              ]
            end
          end
        end
      end
    end
  end
end
