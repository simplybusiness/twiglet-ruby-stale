# frozen_string_literal: true

require 'logger'
require 'time'
require 'json'

require_relative '../hash_extensions'

module Twiglet
  class Logger < ::Logger
    def initialize(
      service_name,
      default_properties: {},
      now: -> { Time.now.utc },
      output: $stdout
    )
      @service_name = service_name
      @now = now
      @default_properties = default_properties
      @output = output

      raise 'Service name is mandatory' \
        unless service_name.is_a?(String) && !service_name.strip.empty?

      formatter = Formatter.new(
        service_name: service_name,
        default_properties: default_properties,
        now: now
      )
      super(output, formatter: formatter)
    end

    alias_method :critical, :fatal
    alias_method :warning, :warn

    def with(default_properties)
      Twiglet::Logger.new(@service_name,
                          default_properties: default_properties,
                          now: @now,
                          output: @output)
    end

    def error(progname = nil, error = nil, &block)
      if error
        error_msg = {
          'error': {
            'message': error.message
          }
        }
        add_stack_trace(error_msg, error)
        message = progname.key?(:message) ? progname : { message: progname }
        error_msg.merge!(message)
        super(error_msg, &block)
      else
        super(progname, &block)
      end
    end

    private

    def add_stack_trace(hash_to_add_to, error)
      hash_to_add_to[:error][:stack_trace] = error.backtrace.join("\n") if error.backtrace
    end

    class Formatter < ::Logger::Formatter
      Hash.include HashExtensions

      def initialize(
        service_name:,
        default_properties:,
        now:
      )
        @service_name = service_name
        @default_properties = default_properties
        @now = now
        super()
      end

      def call(severity, _time, _progname, msg)
        level = severity.downcase
        log(level: level, message: msg)
      end

      private

      def log(level:, message:)
        case message
        when String
          log_text(level, message: message)
        when Hash
          log_object(level, message: message)
        else
          super.call
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

        base_message
          .deep_merge(@default_properties.to_nested)
          .deep_merge(message.to_nested)
          .to_json
      end
    end
  end
end
