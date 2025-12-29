# @summary Trigger bulk Hub verification calls for applicants with specified evidences in pending status and emit a CSV report.
#
# @description
# - Requires one or more evidence keys via ARGV[0] (comma-separated).
# - Requires a reason for the verification request via ARGV[1].
# - Requires a comma-separated list of Family IDs via ARGV[2].
# - Invokes Operations::BulkProcess::CallHubForPendingEvidence to request Hub verification
#   for applicants whose evidences are pending, then prints the CSV report path or error.
#
# @usage
#   bundle exec rails runner script/call_hub_for_applicants_with_evidence_in_pending_status.rb "social_security_number_evidence" "Bulk Hub Call for Pending Evidences: CRM 28618" "64f9a2...,64f9b3...,64f9c4..."
#
# @example Run with multiple evidence types, a reason, and explicit families
#   EVIDENCE_TYPES="social_security_number_evidence,citizenship_evidence"
#   REASON="Bulk Hub Call for Pending Evidence: CRM 28618"
#   FAMILY_IDS="64f9a2...,64f9b3...,64f9c4..."
#   bundle exec rails runner script/call_hub_for_applicants_with_evidence_in_pending_status.rb "$EVIDENCE_TYPES" "$REASON" "$FAMILY_IDS"
#
# @note
# - Evidence keys must match evidence.key values (e.g., social_security_number_evidence).
# - Family IDs must be BSON::ObjectId strings, comma-separated with no spaces.
#
# @output
# - STDOUT: "CSV Report Generated at: <path>" on success
# - STDERR: "Error Occurred: <message>" on failure
#
# @see Operations::BulkProcess::CallHubForPendingEvidence
#
# @section Arguments (ARGV)
# @param [String] ARGV[0] (required) evidence type (e.g., "social_security_number_evidence").
# @param [String] ARGV[1] (required) Reason for the verification request (free text).
# @param [String] ARGV[2] (required) Comma-separated Family IDs (BSON::ObjectId strings).
#
# @return [void]
# @raise SystemExit Exits with a non-zero status if required arguments are missing or invalid.
if ARGV[0].present?
  evidence_type = ARGV[0]
else
  puts "Error: evidence_type(s) missing.\nUsage: bundle exec rails runner script/call_hub_for_applicants_with_evidence_in_pending_status.rb \"social_security_number_evidence\" \"Reason text\" \"<family_id_1>,<family_id_2>,...\""
  exit
end

if ARGV[1].present?
  reason_for_verification_request = ARGV[1]
else
  puts "Error: reason_for_verification_request missing.\nUsage: bundle exec rails runner script/call_hub_for_applicants_with_evidence_in_pending_status.rb \"social_security_number_evidence\" \"Reason text\" \"<family_id_1>,<family_id_2>,...\""
  exit
end

if ARGV[2].present?
  family_ids = ARGV[2].split(',') 
else
  puts "Error: family_ids missing.\nUsage: bundle exec rails runner script/call_hub_for_applicants_with_evidence_in_pending_status.rb \"social_security_number_evidence\" \"Reason text\" \"<family_id_1>,<family_id_2>,...\""
  exit
end

result = Operations::BulkProcess::CallHubForPendingEvidence.new.call(
  {
    family_ids: family_ids,
    evidence_type: evidence_type,
    reason_for_verification_request: reason_for_verification_request
  }
)

if result.success?
  puts "CSV Report Generated at: #{result.success}"
else
  puts "Error Occurred: #{result.failure}"
end