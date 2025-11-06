# frozen_string_literal: true

# Fix completed evidences that incorrectly have due_on dates set
#
# Completed evidences (verified, attested, etc.) should not have due dates.
# Only pending evidences (outstanding, review, rejected) should have due_on set.
#
# Usage:
#   # Generate impact report first
#   `bundle exec rake completed_evidence_due_dates:generate_impact_list`
#
#   # Fix the data (clears due_on for completed evidences)
#   `bundle exec rake completed_evidence_due_dates:fix`
#
# Output: CSV files saved to Rails.root as completed_evidence_impact_YYYY_MM_DD.csv

require 'csv'

namespace :completed_evidence_due_dates do
  
  desc "Clear due_on for completed evidences that shouldn't have due dates"
  task fix: :environment do
    def find_affected_applications(namespace)
      namespace::Application.where(
        'applicants' => {
          '$elemMatch' => {
            'eligibilities' => {
              '$elemMatch' => {
                'evidences' => {
                  '$elemMatch' => {
                    'current_state' => { '$nin' => ['rejected', 'outstanding', 'review'] },
                    'due_on' => { '$ne' => nil }
                  }
                }
              }
            }
          }
        }
      )
    end

    def evidence_needs_processing?(evidence)
      evidence.current_state.present? && 
      ![:rejected, :outstanding, :review].include?(evidence.current_state.to_sym) && 
      evidence.due_on.present?
    end

    def each_affected_evidence(&block)
      fa_apps = find_affected_applications(FinancialAssistance)
      im_apps = find_affected_applications(IndividualMarket)

      total_apps = fa_apps.count + im_apps.count
      puts "Found #{total_apps} applications with evidences to process."
      
      app_index = 0
      [fa_apps, im_apps].each do |apps|
        apps.each do |app|
          app_index += 1
          offset_index = app_index
          puts "Processing Application (#{offset_index}/#{total_apps})" if offset_index % 1000 == 0
          
          app.applicants.each do |applicant|
            applicant.eligibilities.each do |eligibility|
              eligibility.evidences.each do |evidence|
                next unless evidence_needs_processing?(evidence)
                
                block.call(app, applicant, eligibility, evidence)
              end
            end
          end
        end
      end
    end

    puts "Starting data fix to clear due_on for completed evidences..."
    
    updated_count = 0
    
    each_affected_evidence do |app, applicant, eligibility, evidence|
      evidence.set(due_on: nil)
      updated_count += 1
    end

    puts "due_on updated for #{updated_count} evidences. Please rebuild family determinations."
  end

  desc "Generate impact list for completed evidences with due_on set"
  task generate_impact_list: :environment do
    def find_affected_applications(namespace)
      namespace::Application.where(
        'applicants' => {
          '$elemMatch' => {
            'eligibilities' => {
              '$elemMatch' => {
                'evidences' => {
                  '$elemMatch' => {
                    'current_state' => { '$nin' => ['rejected', 'outstanding', 'review'] },
                    'due_on' => { '$ne' => nil }
                  }
                }
              }
            }
          }
        }
      )
    end

    def evidence_needs_processing?(evidence)
      evidence.current_state.present? && 
      ![:rejected, :outstanding, :review].include?(evidence.current_state.to_sym) && 
      evidence.due_on.present?
    end

    def each_affected_evidence(&block)
      fa_apps = find_affected_applications(FinancialAssistance)
      im_apps = find_affected_applications(IndividualMarket)

      total_apps = fa_apps.count + im_apps.count
      puts "Found #{total_apps} applications with evidences to process."
      
      app_index = 0
      [fa_apps, im_apps].each do |apps|
        apps.each do |app|
          app_index += 1
          offset_index = app_index
          puts "Processing Application (#{offset_index}/#{total_apps})" if offset_index % 1000 == 0
          
          app.applicants.each do |applicant|
            applicant.eligibilities.each do |eligibility|
              eligibility.evidences.each do |evidence|
                next unless evidence_needs_processing?(evidence)
                
                block.call(app, applicant, eligibility, evidence)
              end
            end
          end
        end
      end
    end

    puts "Generating impact list for completed evidences with due_on set..."
    
    data = []
    each_affected_evidence do |app, applicant, eligibility, evidence|
      last_history = evidence.verification_histories&.last
      if app.is_a?(FinancialAssistance::Application) 
        app_state = app.aasm_state
        person_hbx_id = applicant.person_hbx_id
      else
        app_state = app.current_state
        person_hbx_id = applicant.hbx_id
      end
      data << [
        app.class.name,
        app.hbx_id,
        app.assistance_year,
        app_state,
        person_hbx_id,
        eligibility.key, 
        evidence.key, 
        evidence.current_state, 
        evidence.due_on, 
        last_history&.action,
        last_history&.created_at
      ]
    end

    puts "Generating CSV report with #{data.count} evidence records..."
    
    field_names = [
      "Application Type",
      "Application HBX ID", 
      "Application Assistance Year",
      "Application State",
      "Person HBX ID", 
      "Eligibility Key", 
      "Evidence Key", 
      "Current State", 
      "Due On", 
      "Last Action",
      "Last Action Date"
    ]
    
    file_name = "#{Rails.root}/completed_evidence_impact_#{Date.today.strftime('%Y_%m_%d')}.csv"
    
    csv_content = CSV.generate(force_quotes: true) do |csv|
      csv << field_names
      data.each { |row| csv << row }
    end

    File.write(file_name, csv_content)
    puts "CSV report generated: #{file_name}"
  rescue StandardError => e
    puts "Error generating CSV: #{e.message}"
  end
end
