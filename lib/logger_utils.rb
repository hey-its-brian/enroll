# frozen_string_literal: true

# Utility module that provides enhanced logging capabilities with automatic caller tracking
#
# This module provides methods to log messages with information about the caller's context,
# making it easier to trace the origin of log entries in a complex application.
#
# @example Including the module in a class
#   class MyService
#     include LoggerUtils
#
#     def perform_operation
#       log_info("Operation started")
#       # do something
#       log_debug("Processing complete")
#     end
#   end
#
# @note This module automatically tracks both the immediate and originating callers
module LoggerUtils
  LOGGER_REGEX_PATTERN = %r{/app/\w+/(.+)\.rb:\d+:in\s+[`'](.+)[`']}

  # Finds relevant caller information from the stack trace
  #
  # @param exclude_files [Array<String>] file paths to exclude from caller detection
  # @return [Hash] a hash containing the immediate and originating callers
  # @option return [String] :immediate the immediate caller in the stack
  # @option return [String] :originating the originating caller in the stack
  # @api private
  def find_caller_info(exclude_files = [])
    filtered_stack = caller.select do |call_entry|
      call_entry.include?('/app/') &&
        exclude_files.none? { |file| call_entry.include?(file) }
    end

    {
      immediate: filtered_stack.first,
      originating: filtered_stack.last
    }
  end

  # Extracts human-readable class and method information from a caller entry
  #
  # @param caller_entry [String] a single entry from the call stack
  # @return [String] formatted string showing class and method name
  def extract_caller_identity(caller_entry)
    return "Unknown caller" if caller_entry.blank?

    match_data = caller_entry.match(LOGGER_REGEX_PATTERN)
    if match_data
      class_path = match_data[1]
      method_name = match_data[2]
      "#{class_path}##{method_name}"
    else
      "Unknown caller"
    end
  end

  # Logs a message with caller information
  #
  # @param message [String] the log message to record
  # @param options [Hash] additional logging options
  # @option options [Symbol] :level (:info) the log level to use (:info, :error, :debug, etc.)
  # @return [void]
  def log(message, options = {})
    current_class_path = "#{self.class.name.underscore}.rb"

    caller_info = find_caller_info([current_class_path])

    immediate_caller = extract_caller_identity(caller_info[:immediate])
    originating_caller = extract_caller_identity(caller_info[:originating])

    log_message = "#{message} | " \
                  "immediate caller: #{immediate_caller} | " \
                  "originating caller: #{originating_caller}"

    level = options.fetch(:level, :info)
    Rails.logger.send(level, log_message)
  rescue StandardError => e
    Rails.logger.error("Error while logging: #{e.message}")
  end

  # Logs a message at the info level
  #
  # @param message [String] the log message to record
  # @return [void]
  def log_info(message)
    log(message, level: :info)
  end

  # Logs a message at the error level
  #
  # @param message [String] the log message to record
  # @return [void]
  def log_error(message)
    log(message, level: :error)
  end

  # Logs a message at the debug level
  #
  # @param message [String] the log message to record
  # @return [void]
  def log_debug(message)
    log(message, level: :debug)
  end
end