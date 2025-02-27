# frozen_string_literal: true

#insured/families/verification_history?member=id&verification=id
class IvlVerificationHistory

  def self.transaction_history_breadcrumb
    '.interaction-click-control-transaction-history'
  end

  def self.back_to_individual_btn
    'a[class="button interaction-click-control-back-to-document-detail"]'
  end

end