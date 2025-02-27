# frozen_string_literal: true

#insured/families/verification_detail?member=id&verification=id
class IvlDocumentDetail

  def self.doc_detail_breadcrumb
    '.interaction-click-control-document-detail'
  end

  def self.back_to_individual_top_btn
    'a[class="button interaction-click-control-back-to-individual"]'
  end

  def self.back_to_individual_bottom_btn
    '#previous_button'
  end

  def self.actions_upload_dropdown
    '#dropdown_for_'
  end

  def self.actions_admin_tools_dropdown
    'select[name="verification_actions"]'
  end

  def self.verified
    'option[value="Verify"]'
  end

  def self.reject
    'option[value="Reject"]'
  end

  def self.call_hub
    'option[value="Call HUB"]'
  end

  def self.extend
    'option[value="Extend"]'
  end

  def self.reason_dropdown
    '#verification_reason'
  end

  def self.doc_in_enroll_app
    'option[value="Document in EnrollApp"]'
  end

  def self.doc_in_dims
    'option[value="Document in DIMS"]'
  end

  def self.save_system
    'option[value="SAVE system"]'
  end

  def self.e_verified_in_curam
    'option[value="E-Verified in Curam"]'
  end

  def self.salesforce
    'option[value="Salesforce"]'
  end

  def self.self_attestation
    'option[value="Self-Attestation"]'
  end

  def self.confirm
    '.interaction-click-control-confirm'
  end

  def self.cancel
    '.interaction-click-control-cancel'
  end

  def self.verification_history_link
    'a[href^="/insured/families/verification_history"]'
  end

end
