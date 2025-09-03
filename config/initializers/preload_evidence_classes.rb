# frozen_string_literal: true

# Preload all evidence classes to prevent STI class loading issues
# This ensures that Mongoid's Single Table Inheritance works reliably
# by having all subclasses loaded in memory at application startup.

# @rails @mongoid @mongodb
#
# @note This is a temporary measure to address the STI class loading issues.
# This code needs to be removed and regression tested on every Major Rails/Mongoid upgrade.
Rails.application.config.after_initialize do
  # Individual Market and Financial Assistance Evidence classes
  [
    'Eligibilities::V3::Evidences::AliveEvidence',
    'Eligibilities::V3::Evidences::AmericanIndianEvidence',
    'Eligibilities::V3::Evidences::CitizenshipEvidence',
    'Eligibilities::V3::Evidences::ImmigrationEvidence',
    'Eligibilities::V3::Evidences::SocialSecurityNumberEvidence',
    'FinancialAssistance::Evidences::IncomeEvidence',
    'FinancialAssistance::Evidences::EsiMecEvidence',
    'FinancialAssistance::Evidences::NonEsiMecEvidence',
    'FinancialAssistance::Evidences::LocalMecEvidence'
  ].each do |evidence_class|
    # Check if class is already loaded by trying to safe_constantize.
    # This will return the class if it's already loaded, or nil if not found.
    klass = evidence_class.safe_constantize
    if klass
      Rails.logger.debug "Evidence class already loaded: #{evidence_class}"
    else
      # Class not loaded, so load it now
      begin
        evidence_class.constantize
        Rails.logger.debug "Preloaded evidence class: #{evidence_class}"
      rescue NameError => e
        Rails.logger.error "Failed to preload evidence class #{evidence_class}: #{e.message}"
        raise "Critical error: Unable to preload evidence class #{evidence_class}. This may cause STI functionality to fail. Error: #{e.message}"
      end
    end
  end
end
