# frozen_string_literal: true

if defined?(FactoryBot)
  module FactoryBot
    # Extend FactoryBot with custom sequence generation methods
    module SequenceExtensions
      # Generate a sequence of letters (A, B, C, ..., Z, AA, AB, ...)
      # @param name [Symbol] the name of the sequence
      # @param formatter [Proc] optional block to format the letter sequence
      # @return [void]
      def letter_sequence(name, &formatter)
        custom_sequence(name, LetterSequenceGenerator.new, &formatter)
      end

      private

      # Creates a FactoryBot sequence using a custom generator strategy
      # This method is encapsulated as private to hide implementation details
      # @param name [Symbol] the name of the sequence
      # @param generator [#call] an object that responds to call(n) and generates a value
      # @param formatter [Proc] optional block to format the generated value
      # @return [void]
      def custom_sequence(name, generator, &formatter)
        sequence(name) do |n|
          value = generator.call(n)
          formatter ? formatter.call(value) : value
        end
      end

      # Base class for sequence generators
      class BaseSequenceGenerator
        # Generate a value for the given sequence number
        # @param n [Integer] the sequence number (1-indexed)
        # @return [String] the generated value
        # @raise [NotImplementedError] if not implemented by subclass
        def call(n) # rubocop:disable Naming/MethodParameterName
          generate_value(n)
        end

        private

        # Generate the actual sequence value - to be implemented by subclasses
        # @param _n [Integer] the validated sequence number
        # @return [String] the generated value
        # @raise [NotImplementedError] if not implemented by subclass
        def generate_value(_n) # rubocop:disable Naming/MethodParameterName
          raise NotImplementedError, "#{self.class} must implement #generate_value"
        end
      end

      # Generates letter sequences using base-26 encoding (A, B, ..., Z, AA, AB, ...)
      class LetterSequenceGenerator < BaseSequenceGenerator
        # ASCII value for 'A' - base for letter sequence calculation
        LETTER_A_ASCII = 'A'.ord
        ALPHABET_SIZE = 26

        private

        # Convert a number to its corresponding letter sequence using base-26 encoding
        # @param n [Integer] the number to convert (must be positive)
        # @return [String] the corresponding letter sequence
        # @example
        #   generate_value(1)  #=> 'A'
        #   generate_value(26) #=> 'Z'
        #   generate_value(27) #=> 'AA'
        #   generate_value(28) #=> 'AB'
        #   generate_value(703) #=> 'AAA'
        def generate_value(n) # rubocop:disable Naming/MethodParameterName
          result = ""
          current = n

          while current > 0
            current -= 1
            result = (LETTER_A_ASCII + (current % ALPHABET_SIZE)).chr + result
            current /= ALPHABET_SIZE
          end

          result
        end
      end
    end
  end

  FactoryBot::DefinitionProxy.include FactoryBot::SequenceExtensions
end
