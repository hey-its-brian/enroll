# frozen_string_literal: true

module Forms
  # AssisterOrgIdField form
  module AssisterOrgIdField
    def self.included(base)
      base.class_eval do
        attr_reader :assister_org_id

        def assister_org_id=(new_assister_org_id)
          @assister_org_id = new_assister_org_id.to_s.gsub(/\D/, '') unless new_assister_org_id.blank?
        end
      end
    end
  end
end
