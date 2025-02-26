# frozen_string_literal: true

module BenefitSponsors
  module Queries
    # query class for assister datatable
    class AssisterApplicantsDatatableQuery

      attr_reader :search_string, :custom_attributes

      def datatable_search(string)
        @search_string = string
        self
      end

      def initialize(attributes)
        @custom_attributes = attributes
      end

      def person_search(search_string)
        ::Person.exists(assister_role: true).assister_role_having_agency if search_string.blank?
      end

      def build_scope
        ::Person.exists(assister_role: true).assister_role_having_agency.order_by(created_at: :desc)
      end

      def skip(num)
        build_scope.skip(num)
      end

      def limit(num)
        build_scope.limit(num)
      end

      def order_by(var)
        @order_by = var
        self
      end

      def klass
        ::Person.exists(assister_role: true).assister_role_having_agency
      end

      def size
        build_scope.count
      end

    end
  end
end
