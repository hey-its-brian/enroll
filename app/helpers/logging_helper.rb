# frozen_string_literal: true

# Helper file to log messages
module LoggingHelper
  # Logs a message with the specified log level
  #
  # @param message [String] The message to log
  # @param type [Symbol] The type of log message (:info, :error, or other for :debug)
  # @param logger [Logger] The logger to use (defaults to Rails.logger)
  # @return [void]
  # @example Log an info message
  #   log_message("User account created", :info)
  # @example Log an error message with custom logger
  #   log_message("Database connection failed", :error, custom_logger)
  def log_message(message, type = :info, logger = Rails.logger)
    return if Rails.env.test?

    case type
    when :info
      logger.info(message)
    when :error
      logger.error(message)
    else
      logger.debug(message)
    end
  end
end
