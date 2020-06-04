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
        message = message.merge({
                                  error_name: error.message,
                                  backtrace: error.backtrace
                                })
      end

      log(level: 'error', message: message)
    end

    def critical(message)
      log(level: 'critical', message: message)
    end

    def with(default_properties)
      Logger.new(@service_name,
                 default_properties: default_properties,
                 now: @now,
                 output: @output)
    end

    private

    def log(level:, message:)
      raise 'Message must be a Hash' unless message.is_a?(Hash)

      message = message.transform_keys(&:to_sym)
      message.key?(:message) || raise('Log object must have a \'message\' property')

      message[:message].strip.empty? && raise('The \'message\' property of log object must not be empty')

      base_message = {
        service: {
          name: @service_name
        },
        "@timestamp": @now.call.iso8601(3),
        log: {
          level: level
        }
      }

      @output.puts base_message
                     .deep_merge(@default_properties.to_nested)
                     .deep_merge(message.to_nested)
                     .to_json
    end
  end
end
