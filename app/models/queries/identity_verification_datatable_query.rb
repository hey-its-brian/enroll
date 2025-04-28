# frozen_string_literal: true

module Queries
  class IdentityVerificationDatatableQuery
    include Sorter

    attr_reader :search_string, :custom_attributes

    AGGREGATABLE_COLUMNS = {"name" => :sort_by_full_name_pipeline}.freeze

    def datatable_search(string)
      @search_string = string
      self
    end

    def initialize(attributes)
      @custom_attributes = attributes
    end

    def build_scope
      people = EnrollRegistry.feature_enabled?(:show_people_with_no_evidence) ? identity_verifications_table_query : Person.for_admin_approval_with_documents
      #add other scopes here
      return people if @search_string.blank? || @search_string.length < 2
      person_id = Person.search(@search_string).pluck(:_id)
      #Caution Mongo optimization on chained "$in" statements with same field
      #is to do a union, not an interactionl
      people.and('_id' => {"$in" => person_id})
    end

    # Find people with pending/rejected identity or application validation
    # who either have no associated user document or have a non-accepted identity response
    def identity_verifications_table_query
      match_criteria = if EnrollRegistry.feature_enabled?(:application_validation_in_identity_verification)
                         { "$or" => [
                           { "consumer_role.identity_validation" => { "$in" => [:pending, :rejected] } },
                           { "consumer_role.application_validation" => { "$in" => [:pending, :rejected] } }
                         ]}
                       else
                         { "consumer_role.identity_validation" => { "$in" => [:pending, :rejected] } }
                       end
      person_ids = Person.collection.aggregate([
                                                 # Stage 1: Match people with pending or rejected validations
                                                 { "$match" => match_criteria },
                                                 # Stage 2: Join with users collection
                                                 { "$lookup" => {
                                                   from: "users",
                                                   localField: "user_id",
                                                   foreignField: "_id",
                                                   as: "user_docs"
                                                 }},
                                                 # Stage 3: Filter for records with no user docs or non-accepted response code
                                                 { "$match" => {
                                                   "$or" => [
                                                     { "user_docs" => { "$size" => 0 } },
                                                     { "user_docs.identity_response_code" => { "$ne" => "acc" } }
                                                   ]
                                                 }},
                                                 # Stage 4: Project only _id field
                                                 { "$project" => { "_id" => 1 }}
                                               ], { allowDiskUse: true }).map { |rec| rec["_id"] }

      Person.where(:_id => {"$in" => person_ids})
    end

    def build_query
      limited_scope = build_scope
      limited_scope = sort_query(limited_scope, @order_by) if @order_by
      paginate(limited_scope)
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

    def each(&block)
      return to_enum(:each) unless block

      build_query.each(&block)
    end

    def each_with_index(&block)
      return to_enum(:each_with_index) unless block

      build_query.each_with_index(&block)
    end

    def klass
      Person
    end

    def size
      build_scope.count
    end

  end
end
