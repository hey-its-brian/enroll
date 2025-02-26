module BenefitSponsors
  module Forms
    module NpnField

      def self.included(base)
        base.class_eval do
          attr_reader :npn, :assister_org_id

          def npn=(new_npn)
            if !new_npn.blank?
              @npn = new_npn.to_s.gsub(/\D/, '')
            end
          end

          def assister_org_id=(new_assister_org_id)
            @assister_org_id = new_assister_org_id.to_s.gsub(/\D/, '') unless new_assister_org_id.blank?
          end
        end
      end
    end
  end
end