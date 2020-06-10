# frozen_string_literal: true

require 'time'
require 'json'
require_relative '../hash_extensions'

module Twiglet
  class Logger
    Hash.include HashExtensions

    def initialize(
      service_name,
      default_properties: {},
      now: -> { Time.now.utc },
      output: $stdout
    )
      @service_name = service_name
      @now = now
      @output = output

      raise 'Service name is mandatory' \
        unless @service_name.is_a?(String) && !@service_name.strip.empty?

      @default_properties = default_properties
    end

    def debug(message)
      log(level: 'debug', message: message)
    end

    def info(message)
      log(level: 'info', message: message)
    end

    def warning(message)
      log(level: 'warning', message: message)
    end

    alias_method :warn, :warning

    def error(message, error = nil)
      if error
        error_fields = {
          'error': {
            'message': error.message
          }
        }
        add_stack_trace(error_fields, error)
        message = message.merge(error_fields)
      end

      log(level: 'error', message: message)
    end

    def critical(message)
      log(level: 'critical', message: message)
    end

    alias_method :fatal, :critical

    def with(default_properties)
      Logger.new(@service_name,
                 default_properties: default_properties,
                 now: @now,
                 output: @output)
    end

    private

    def log(level:, message:)
      case message
      when String
        log_text(level, message: message)
      when Hash
        log_object(level, message: message)
      else
        raise('Message must be String or Hash')
      end
    end

    def log_text(level, message:)
      raise('The \'message\' property of log object must not be empty') if message.strip.empty?

      message = { message: message }
      log_message(level, message: message)
    end

    def log_object(level, message:)
      message = message.transform_keys(&:to_sym)
      message.key?(:message) || raise('Log object must have a \'message\' property')
      message[:message].strip.empty? && raise('The \'message\' property of log object must not be empty')

      log_message(level, message: message)
    end

    def log_message(level, message:)
      base_message = {
        "@timestamp": @now.call.iso8601(3),
        service: {
          name: @service_name
        },
        log: {
          level: level
        }
      }

      @output.puts base_message
                       .deep_merge(@default_properties.to_nested)
                       .deep_merge(message.to_nested)
                       .to_json
    end

    def add_stack_trace(hash_to_add_to, error)
      hash_to_add_to[:error][:stack_trace] = error.backtrace.join("\n") if error.backtrace
    end
  end
end
