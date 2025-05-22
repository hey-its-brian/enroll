# frozen_string_literal: true

# The HasDocument concern provides document attachment capabilities to models
# where it's included.
#
# This concern is designed to be mixed into models that need to associate
# document records with them. It establishes a Mongoid embedded relationship
# between the including model and the Document class.
#
# @example Including in a model
#   class Person
#     include Mongoid::Document
#     include HasDocument
#     # ...
#   end
#
# @note When included in a model, instances of that model will have access
#   to the documents collection and associated methods for managing documents.
module HasDocument
  extend ActiveSupport::Concern

  included do
    embeds_many :documents, class_name: '::Document', as: :documentable, cascade_callbacks: true
    # embeds_many :comments, class_name: '::Comment', as: :commentable
  end
end
