# frozen_string_literal: true
require 'logger'
require 'time'
require 'json'
require_relative '../hash_extensions'

module Twiglet
  class Logger
    attr_accessor :logging
    def initialize(
        service_name,
        default_properties: {},
        now: -> { Time.now.utc },
        output: $stdout
    )
      formatter = TwigFormat.new
      formatter.service_name = service_name
      formatter.now = now
      formatter.output = output

      raise 'Service name is mandatory' \
        unless service_name.is_a?(String) && !service_name.strip.empty?

      formatter.default_properties = default_properties

      @logging = ::Logger.new(output, formatter: formatter)
    end
  end

  class TwigFormat < ::Logger::Formatter
    attr_accessor :service_name, :now, :default_properties, :output
    Hash.include HashExtensions

    def call(severity, time, progname, msg)
      log_twig(level: severity, message: msg).to_json
    end

    private

    def log_twig(level:, message:)
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
          "@timestamp": now.call.iso8601(3),
          service: {
              name: service_name
          },
          log: {
              level: level
          }
      }

      base_message
                 .deep_merge(default_properties.to_nested)
                 .deep_merge(message.to_nested)
    end

    def add_stack_trace(hash_to_add_to, error)
      hash_to_add_to[:error][:stack_trace] = error.backtrace.join("\n") if error.backtrace
    end

    def with(default_properties)
      Logger.new(service_name,
                 default_properties: default_properties,
                 now: now,
                 output: output)
    end
  end
end
