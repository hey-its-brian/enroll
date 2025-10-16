# frozen_string_literal: true

# This script generates a CSV report with list of all the
# IndividualMarket::Applications with the is_renewal field populated with true
# and has same assistance_year as input.
# rails runner script/qhp_renewal_application_report.rb '2026' -e production

assistance_year = if ARGV[0].present? && ARGV[0].to_i.to_s == ARGV[0]
                    ARGV[0].to_i
                  else
                    TimeKeeper.date_of_record.year.next
                  end

result = ::Operations::IndividualMarket::Applications::Renewals::GenerateQhpRenewalApplicationsReport.new.call(
  assistance_year: assistance_year
)

if result.success?
  puts "QHP Renewal Application Report generated successfully at #{result.success}"
else
  puts "Failed to generate QHP Renewal Application Report. Message: #{result.failure}"
end
