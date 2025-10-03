# Script to create APTC/CSR evidences for applicants on Financial Assistance applications.
#
# This script accepts a comma-separated list of Application HBX IDs and, for each,
# invokes Operations::DataFixes::CreateAptcCsrEvidences to ensure Income / ESI / Non-ESI /
# Local MEC evidence records are established (and transitioned) for the application's applicants.
#
# Results (per applicant per evidence) are accumulated and exported to one or more CSV files.
# Large result sets are split automatically into files of at most 500,000 rows to keep file sizes manageable.
#
# INPUT
#   ARGV[0] - A comma‑separated list of Application HBX IDs
#
# OUTPUT
#   One or more CSV files named: "evidences report 0.csv", "evidences report 1.csv", ...
#   Each row structure:
#     family_id,
#     application_hbx_id,
#     application_state,
#     application_created_at,
#     primary_person_hbx_id,
#     applicant_person_hbx_id,
#     is_applying_coverage,
#     evidence_type,
#     evidence_state,
#     message
#
# EXAMPLES
#   CLIENT=me bundle exec rails runner script/data_fixes/create_aptc_csr_evidences.rb "12345,67890"
#   CLIENT=me bundle exec rails runner script/data_fixes/create_aptc_csr_evidences.rb
#     (prints an error and exits if no IDs provided)
#
# NOTES
#   - The operation currently receives each ID as :person_hbx_id (historical param name),
#     though values supplied are Application HBX IDs. Align names in a future refactor.
#   - Timing is captured via Caches::BenchmarkCache.
#
# @see Operations::DataFixes::CreateAptcCsrEvidences
# @see Caches::BenchmarkCache
#
# @raise [SystemExit] if no valid IDs are provided
# @return [void]
p '********** STARTING - Script to create APTC/CSR evidences **********'

# Generates one or more CSV files from the collected evidence rows.
#
# @param array_collection [Array<Array>] Array of row arrays. Each inner array must match the
#   header order:
#     ["family_id", "application_hbx_id", "application_state", "application_created_at",
#      "primary_person_hbx_id", "applicant_person_hbx_id", "is_applying_coverage",
#      "evidence_type", "evidence_state", "message"]
# @return [Array<String>] Filenames generated (one per 500,000 rows slice)
# @raise [StandardError] if file writing fails
def generate_csv_file(array_collection)
  file_name = []

  array_collection.each_slice(500_000).with_index do |limited_array, index|
    FileUtils.touch("evidences report #{index}.csv") unless File.exist?("evidences report #{index}.csv")

    csv_content = CSV.generate(force_quotes: true) do |csv|
      csv << ["family_id", "application_hbx_id", "application_state", "application_created_at", "primary_person_hbx_id", "applicant_person_hbx_id", "is_applying_coverage", "evidence_type", "evidence_state", "message"]
      limited_array.each { |row| csv << row }
    end

    File.write("evidences report #{index}.csv", csv_content)
    file_name << "evidences report #{index}.csv"
  end
  file_name
end

# Measures total execution time for processing provided Application HBX IDs.
#
# @return [Float] Elapsed seconds (stored in elapsed_time local)
elapsed_time = Caches::BenchmarkCache.with_benchmark do
  list = ARGV[0].present? ? ARGV[0] : ""

  application_hbx_ids = list.split(',').map(&:strip).reject(&:empty?)

  if application_hbx_ids.empty?
    puts "Error: No valid HBX IDs provided"
    exit 1
  end

  array_collection = []
  application_hbx_ids.each do |application_hbx_id|
    # NOTE: Parameter key still named :person_hbx_id in the operation signature.
    # result = ::Operations::DataFixes::CreateAptcCsrEvidences.new.call({ person_hbx_id: application_hbx_id })

    if result.success?
      array_collection.push(*result.value!)
    else
      puts result.failure
      array_collection << ['', application_hbx_id, '', '', '', '', '', '', '', result.failure]
    end
  end

  generate_csv_file(array_collection)
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to create APTC/CSR evidences. **********"