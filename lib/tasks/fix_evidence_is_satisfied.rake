# frozen_string_literal: true

# Fix evidences that are in completed states but have is_satisfied not set to true
#
# Evidences in completed states (verified, attested, negative_response_received) should have is_satisfied: true.
# This task identifies and fixes evidences where is_satisfied is not true for these completed states.
#
# Usage:
#   # Generate impact report first
#   `bundle exec rake fix_evidence_is_satisfied:generate_impact_list`
#
#   # Fix the data (sets is_satisfied to true for completed evidences)
#   `bundle exec rake fix_evidence_is_satisfied:fix`
#
# Output: CSV files saved to Rails.root as evidence_is_satisfied_impact_YYYY_MM_DD.csv

require 'csv'

namespace :fix_evidence_is_satisfied do
  
  desc "Set is_satisfied to true for evidences in completed states"
  task fix: :environment do
    satisfied_states = %i[verified attested negative_response_received unverified pending].freeze

    def find_affected_applications(namespace, assistance_year, satisfied_states)
      query = {
        'applicants' => {
          '$elemMatch' => {
            'eligibilities' => {
              '$elemMatch' => {
                'evidences' => {
                  '$elemMatch' => {
                    'current_state' => { '$in' => satisfied_states },
                    'is_satisfied' => { '$ne' => true }
                  }
                }
              }
            }
          }
        }
      }
      
      if assistance_year
        query['assistance_year'] = assistance_year
      end
      
      namespace::Application.where(query)
    end

    def evidence_needs_processing?(evidence, satisfied_states)
      evidence.current_state.present? && 
      satisfied_states.include?(evidence.current_state.to_sym) && 
      evidence.is_satisfied != true
    end
    puts "Starting data fix to set is_satisfied to true for completed evidences..."
    
    updated_count = 0
    eligibility_count = 0
    
    fa_apps = find_affected_applications(FinancialAssistance, 2026, satisfied_states)
    im_apps = find_affected_applications(IndividualMarket, 2026, satisfied_states)

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
            affected_evidences = eligibility.evidences.select { |evidence| evidence_needs_processing?(evidence, satisfied_states) }
            next if affected_evidences.empty?

            affected_evidences.each do |evidence|
              evidence.is_satisfied = true
              updated_count += 1
            end
            
            eligibility.determine_eligibility_state("Retained evidence information from another eligibility")
            eligibility_count += 1
          end
        end
        
        begin
          app.save!
        rescue StandardError => e
          puts "Error saving application #{app.hbx_id}: #{e.message}"
          puts "Skipping this application and continuing..."
        end
      end
    end

    puts "is_satisfied updated for #{updated_count} evidences across #{eligibility_count} eligibilities. Please rebuild family determinations."
  end

  desc "Generate impact list for evidences in completed states with is_satisfied not true"
  task generate_impact_list: :environment do
    satisfied_states = %i[verified attested negative_response_received unverified pending].freeze

    def find_affected_applications(namespace, assistance_year, satisfied_states)
      query = {
        'applicants' => {
          '$elemMatch' => {
            'eligibilities' => {
              '$elemMatch' => {
                'evidences' => {
                  '$elemMatch' => {
                    'current_state' => { '$in' => satisfied_states },
                    'is_satisfied' => { '$ne' => true }
                  }
                }
              }
            }
          }
        }
      }
      
      if assistance_year
        query['assistance_year'] = assistance_year
      end
      
      namespace::Application.where(query)
    end

    def evidence_needs_processing?(evidence, satisfied_states)
      evidence.current_state.present? && 
      satisfied_states.include?(evidence.current_state.to_sym) && 
      evidence.is_satisfied != true
    end

    puts "Generating impact list for evidences in completed states with is_satisfied not true..."
    
    data = []
    
    fa_apps = find_affected_applications(FinancialAssistance, nil, satisfied_states)
    im_apps = find_affected_applications(IndividualMarket, nil, satisfied_states)

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
              next unless evidence_needs_processing?(evidence, satisfied_states)
              
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
                evidence.is_satisfied, 
                last_history&.action,
                last_history&.created_at
              ]
            end
          end
        end
      end
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
      "Due on",
      "Is Satisfied", 
      "Last Action",
      "Last Action Date"
    ]
    
    file_name = "#{Rails.root}/evidence_is_satisfied_impact_#{Date.today.strftime('%Y_%m_%d')}.csv"
    
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
  