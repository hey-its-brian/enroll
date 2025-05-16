# frozen_string_literal: true

# This class is to persist all calculations made by Operations::BenchmarkProducts::IdentifySlcspWithPediatricDentalCosts.
# This class persists both request_payload and response_payload in JSON format.
class BenchmarkProduct
  include Mongoid::Document
  include Mongoid::Timestamps

  field :family_id, type: BSON::ObjectId

  field :application_hbx_id, type: String

  # This field is used to identify the data source of the request.
  # The information that is needed to idetify the benchmark product is either from the family, financial assistance application, or anonymous.
  field :data_source, type: String

  # Constant for data source kinds
  DATA_SOURCE_KINDS = %w[anonymous family fa_application].freeze

  # Validation for data source if it present
  validates :data_source, inclusion: { in: DATA_SOURCE_KINDS }, allow_blank: true

  # Request Payload that is sent to Operations::BenchmarkProducts::IdentifySlcspWithPediatricDentalCosts in JSON format
  field :request_payload, type: String

  # Response Payload that is sent back from Operations::BenchmarkProducts::IdentifySlcspWithPediatricDentalCosts in JSON format
  # This response payload includes all the calculations
  field :response_payload, type: String

  ORIGIN_KINDS = %w[enrollment_purchase application_submission application_aptc_computation].freeze

  # Origin of the request. This is used to identify the source of the request.
  # Possible values are:
  #   enrollment_purchase - when the request is made during enrollment purchase
  #   application_submission - when the request is made during application submission
  #   application_aptc_computation - when the request is made during APTC value calculation
  field :origin, type: String

  # Validates the origin field to ensure it is one of the defined ORIGIN_KINDS if present
  validates :origin, inclusion: { in: ORIGIN_KINDS }, allow_blank: true

  def request
    JSON.parse(request_payload, symbolize_names: true)
  end

  def response
    JSON.parse(response_payload, symbolize_names: true)
  end

  def family
    Family.where(id: family_id).first
  end

  def application
    ::FinancialAssistance::Application.by_hbx_id(application_hbx_id).last
  end
end
