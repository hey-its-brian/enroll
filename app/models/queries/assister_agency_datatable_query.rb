# frozen_string_literal: true

module Queries
  # Wrapper around Mongoid::Criteria to provide datatable search, pagination, and ordering
  class AssisterAgencyDatatableQuery
    include Sorter

    attr_reader :search_string, :custom_attributes

    def datatable_search(string)
      @search_string = string
      self
    end

    def initialize(attributes, data_store:)
      @custom_attributes = attributes
      @data_store = data_store
      @skip = 0
      @limit = 25
    end

    def build_scope
      scope = klass.assister_agency_profiles
      scope = scope.datatable_search(@search_string) if @search_string
      scope
    end

    def build_query
      limited_scope = build_scope
      limited_scope = sort_agency_query(limited_scope, @order_by) if @order_by
      paginate(limited_scope)
    end

    def sort_agency_query(query, order_by)
      return sort_query(query, order_by) unless @order_by.key?("active_families_count")

      count_ordered(query, order_by)
    end

    def each(&block)
      return to_enum(:each) unless block

      build_query.each(&block)
    end

    def each_with_index(&block)
      return to_enum(:each_with_index) unless block

      build_query.each_with_index(&block)
    end

    def skip(num)
      @skip = num
      self
    end

    def limit(num)
      @limit = num
      self
    end

    def order_by(var)
      @order_by = var
      self
    end

    def klass
      BenefitSponsors::Organizations::Organization
    end

    def size
      build_scope.count
    end

    def count_ordered(scope, order_by)
      factor = order_by.values.first == :asc ? 1 : -1
      ordered = scope.to_a.sort_by { |record| factor * @data_store.fetch_field(record) }
      ordered[@skip..(@skip + @limit)]
    end
  end
end
