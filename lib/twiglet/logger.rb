# frozen_string_literal: true

require 'time'
require 'json'
require_relative '../elastic_common_schema'

module Twiglet
  class Logger
    include ElasticCommonSchema

    def initialize(
      service_name,
      scoped_properties: {},
      now: -> { Time.now.utc },
      output: $stdout
    )
      @service_name = service_name
      @now = now
      @output = output

      raise 'configuration must have a service name' \
        unless @service_name.is_a?(String) && !@service_name.strip.empty?

      @scoped_properties = scoped_properties
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

    def with(scoped_properties)
      Logger.new(@service_name,
                 scoped_properties: scoped_properties,
                 now: @now,
                 output: @output)
    end

    private

    def log(level:, message:)
      raise 'Message must be a Hash' unless message.is_a?(Hash)

      message = message.transform_keys(&:to_sym)
      message.key?(:message) || raise('Log object must have a \'message\' property')

      message[:message].strip.empty? && raise('The \'message\' property of log object must not be empty')

      total_message = {
        service: {
          name: @service_name
        },
        "@timestamp": @now.call.iso8601(3),
        log: {
          level: level
        }
      }
      total_message = deep_merge(total_message, to_nested(@scoped_properties))
      total_message = deep_merge(total_message, to_nested(message))

      @output.puts total_message.to_json
    end
  end
end
