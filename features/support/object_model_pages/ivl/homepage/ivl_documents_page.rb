# frozen_string_literal: true

#insured/families/verification?tab=verification
class IvlDocumentsPage

  def self.docs_we_accept_btn
    '.interaction-click-control-documents-we-accept'
  end

  def self.medicare_and_tax_credit_btn
    '.interaction-click-control-go-to-district-direct'
  end

  def self.income_evidence
    '#evidence_kind_income_evidence'
  end

  def self.income_evidence_row_for(name)
    "[data-cuke='income_evidence_for_#{name.parameterize.underscore}']"
  end

  def self.esi_evidence_row_for(name)
    "[data-cuke='esi_evidence_for_#{name.parameterize.underscore}']"
  end

  def self.local_mec_evidence_actions
    "#v-action-#{@applicant.id}-local-mec"
  end

  def self.view_history_option
    "//div[@class='selectric-scroll']/ul/li[contains(text(), 'View History')]"
  end

  def self.call_hub_option
    "//div[@class='selectric-scroll']/ul/li[contains(text(), 'Call HUB')]"
  end

  def self.verify_option
    "//div[@class='selectric-scroll']/ul/li[contains(text(), 'Verify')]"
  end

  def self.action_items_section
    '[data-cuke="action-items"]'
  end

  def self.household_members_section
    '[data-cuke="household-members"]'
  end

  def self.unverified_member_icon
    '[data-cuke="unverified-member-icon"]'
  end

  def self.summary_header
    '[data-cuke="summary-header"]'
  end

  def self.actionable_status_icon
    '[data-cuke="actionable-status-icon"]'
  end

  def self.upload_documents_section
    '[data-cuke="upload-documents"]'
  end

  def self.individual_verifications_section
    '[data-cuke="individual-verifications"]'
  end
end
