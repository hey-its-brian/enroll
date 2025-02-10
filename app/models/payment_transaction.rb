class PaymentTransaction
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :family, index: true

  field :payment_transaction_id, type: String
  field :carrier_id, type: BSON::ObjectId
  field :enrollment_effective_date, type: Date
  field :enrollment_id, type: BSON::ObjectId
  field :status, type: String
  field :body, type: String
  field :submitted_at, type: DateTime
  field :source, type: String

  index({ status: 1 })
  index({ enrollment_id: 1 })
  index({ enrollment_effective_date: 1 })

  # @!index [Hash] Creates an index on the payment_transaction_id field
  # @param payment_transaction_id [Integer] The ID of the payment transaction.
  # @option options [Boolean] :unique (true) Ensures the index is unique.
  index({ payment_transaction_id: 1 }, { unique: true })
  index({ carrier_id: 1 })

  before_save :generate_payment_transaction_id, :set_submitted_at

  def generate_payment_transaction_id
    write_attribute(:payment_transaction_id, HbxIdGenerator.generate_payment_transaction_id) if payment_transaction_id.blank?
  end

  def set_submitted_at
    self.submitted_at ||= TimeKeeper.datetime_of_record
  end

  def update_enrollment_details(enrollment, source)
    self.enrollment_id = enrollment.id
    self.source = source
    self.carrier_id =  enrollment.product.issuer_profile_id
    self.enrollment_effective_date = enrollment.effective_on
    self.save!
  end

  def self.build_payment_instance(enrollment, source)
    payment = enrollment.family.payment_transactions.build
    payment.update_enrollment_details(enrollment, source)
    payment.family.save!
    payment
  end
end
