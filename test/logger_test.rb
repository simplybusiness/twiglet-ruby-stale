# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/twiglet/logger'

describe Twiglet::Logger do
  before do
    @now = -> { Time.utc(2020, 5, 11, 15, 1, 1) }
    @buffer = StringIO.new
    @logger = Twiglet::Logger.new('petshop',
                                  now: @now,
                                  output: @buffer)
  end

  LEVELS = [
    { method: :debug, level: 'debug' },
    { method: :info, level: 'info' },
    { method: :warning, level: 'warn' },
    { method: :warn, level: 'warn' },
    { method: :critical, level: 'fatal' },
    { method: :fatal, level: 'fatal' },
    { method: :error, level: 'error' }
  ].freeze

  it 'should throw an error with an empty service name' do
    assert_raises RuntimeError do
      Twiglet::Logger.new('  ')
    end
  end

  describe 'JSON logging' do
    it 'should throw an error with an empty message' do
      assert_raises RuntimeError do
        @logger.info({message: ''})
      end
    end

    it 'should log mandatory attributes' do
      @logger.error({message: 'Out of pets exception'})
      actual_log = read_json(@buffer)

      expected_log = {
        message: 'Out of pets exception',
        "@timestamp": '2020-05-11T15:01:01.000Z',
        service: {
          name: 'petshop'
        },
        log: {
          level: 'error'
        }
      }

      assert_equal expected_log, actual_log
    end

    it 'should log the provided message' do
      @logger.error({event:
                       {action: 'exception'},
                     message: 'Emergency! Emergency!'})
      log = read_json(@buffer)

      assert_equal 'exception', log[:event][:action]
      assert_equal 'Emergency! Emergency!', log[:message]
    end

    it 'should log scoped properties defined at creation' do
      extra_properties = {
        trace: {
          id: '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb'
        },
        service: {
          type: 'shop'
        },
        request: {method: 'get'},
        response: {status_code: 200}
      }

      output = StringIO.new
      logger = Twiglet::Logger.new('petshop',
                                   now: @now,
                                   output: output,
                                   default_properties: extra_properties)

      logger.error({message: 'GET /cats'})
      log = read_json output

      assert_equal '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb', log[:trace][:id]
      assert_equal 'petshop', log[:service][:name]
      assert_equal 'shop', log[:service][:type]
      assert_equal 'get', log[:request][:method]
      assert_equal 200, log[:response][:status_code]
    end

    it "should be able to add properties with '.with'" do
      # Let's add some context to this customer journey
      purchase_logger = @logger.with({
                                       trace: {id: '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb'},
                                       customer: {full_name: 'Freda Bloggs'},
                                       event: {action: 'pet purchase'}
                                     })

      # do stuff
      purchase_logger.info({
                             message: 'customer bought a dog',
                             pet: {name: 'Barker', species: 'dog', breed: 'Bitsa'}
                           })

      log = read_json @buffer

      assert_equal '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb', log[:trace][:id]
      assert_equal 'Freda Bloggs', log[:customer][:full_name]
      assert_equal 'pet purchase', log[:event][:action]
      assert_equal 'customer bought a dog', log[:message]
      assert_equal 'Barker', log[:pet][:name]
    end

    it "should log 'message' string property" do
      message = {}
      message['message'] = 'Guinea pigs arrived'
      @logger.debug(message)
      log = read_json(@buffer)

      assert_equal 'Guinea pigs arrived', log[:message]
    end

    it 'should be able to convert dotted keys to nested objects' do
      @logger.debug({
                      "trace.id": '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb',
                      message: 'customer bought a dog',
                      "pet.name": 'Barker',
                      "pet.species": 'dog',
                      "pet.breed": 'Bitsa'
                    })
      log = read_json(@buffer)

      assert_equal '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb', log[:trace][:id]
      assert_equal 'customer bought a dog', log[:message]
      assert_equal 'Barker', log[:pet][:name]
      assert_equal 'dog', log[:pet][:species]
      assert_equal 'Bitsa', log[:pet][:breed]
    end

    it 'should be able to mix dotted keys and nested objects' do
      @logger.debug({
                      "trace.id": '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb',
                      message: 'customer bought a dog',
                      pet: {name: 'Barker', breed: 'Bitsa'},
                      "pet.species": 'dog'
                    })
      log = read_json(@buffer)

      assert_equal '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb', log[:trace][:id]
      assert_equal 'customer bought a dog', log[:message]
      assert_equal 'Barker', log[:pet][:name]
      assert_equal 'dog', log[:pet][:species]
      assert_equal 'Bitsa', log[:pet][:breed]
    end

    it 'should work with mixed string and symbol properties' do
      log = {
        "trace.id": '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb'
      }
      event = {}
      log['event'] = event
      log['message'] = 'customer bought a dog'
      pet = {}
      pet['name'] = 'Barker'
      pet['breed'] = 'Bitsa'
      pet[:species] = 'dog'
      log[:pet] = pet

      @logger.debug(log)
      actual_log = read_json(@buffer)

      assert_equal '1c8a5fb2-fecd-44d8-92a4-449eb2ce4dcb', actual_log[:trace][:id]
      assert_equal 'customer bought a dog', actual_log[:message]
      assert_equal 'Barker', actual_log[:pet][:name]
      assert_equal 'dog', actual_log[:pet][:species]
      assert_equal 'Bitsa', actual_log[:pet][:breed]
    end

    it 'should log an error with backtrace' do
      begin
        1 / 0
      rescue StandardError => e
        @logger.error({message: 'Artificially raised exception'}, e)
      end

      actual_log = read_json(@buffer)

      assert_equal 'Artificially raised exception', actual_log[:message]
      assert_equal 'divided by 0', actual_log[:error][:message]
      assert_match 'logger_test.rb', actual_log[:error][:stack_trace].lines.first
    end

    it 'should log an error without backtrace' do
      e = StandardError.new('Connection timed-out')
      @logger.error({message: 'Artificially raised exception'}, e)

      actual_log = read_json(@buffer)

      assert_equal 'Artificially raised exception', actual_log[:message]
      assert_equal 'Connection timed-out', actual_log[:error][:message]
      refute actual_log[:error].key?(:stack_trace)
    end

    LEVELS.each do |attrs|
      it "should correctly log level when calling #{attrs[:method]}" do
        @logger.public_send(attrs[:method], {message: 'a log message'})
        actual_log = read_json(@buffer)

        assert_equal attrs[:level], actual_log[:log][:level]
        assert_equal 'a log message', actual_log[:message]
      end
    end
  end

  describe 'text logging' do
    it 'should throw an error with an empty message' do
      assert_raises RuntimeError do
        @logger.info('')
      end
    end

    it 'should log mandatory attributes' do
      @logger.error('Out of pets exception')
      actual_log = read_json(@buffer)

      expected_log = {
        message: 'Out of pets exception',
        "@timestamp": '2020-05-11T15:01:01.000Z',
        service: {
          name: 'petshop'
        },
        log: {
          level: 'error'
        }
      }

      assert_equal expected_log, actual_log
    end

    it 'should log the provided message' do
      @logger.error('Emergency! Emergency!')
      log = read_json(@buffer)

      assert_equal 'Emergency! Emergency!', log[:message]
    end

    LEVELS.each do |attrs|
      it "should correctly log level when calling #{attrs[:method]}" do
        @logger.public_send(attrs[:method], 'a log message')
        actual_log = read_json(@buffer)

        assert_equal attrs[:level], actual_log[:log][:level]
        assert_equal 'a log message', actual_log[:message]
      end

      it "should correctly log the block when calling #{attrs[:method]}" do
        block = proc { 'a block log message' }
        @logger.public_send(attrs[:method], &block)
        actual_log = read_json(@buffer)

        assert_equal attrs[:level], actual_log[:log][:level]
        assert_equal 'a block log message', actual_log[:message]
      end
    end
  end

  private

  def read_json(buffer)
    buffer.rewind
    JSON.parse(buffer.read, symbolize_names: true)
  end
end
