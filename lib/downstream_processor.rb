class DownstreamProcessor
  class TransientError < StandardError; end
  class PermanentError < StandardError; end

  def self.call(processing_request)
    new(processing_request).call
  end

  def initialize(processing_request)
    @processing_request = processing_request
  end

  def call
    raise PermanentError, "Request was canceled before processing" if processing_request.canceled?

    case processing_request.simulation_mode
    when "success"
      success_result
    when "slow_success"
      sleep 0.05
      raise PermanentError, "Request was canceled during processing" if processing_request.reload.canceled?

      success_result.merge("duration" => "slow")
    when "fail_once"
      if processing_request.attempts_count == 1
        raise TransientError, "Transient downstream timeout"
      end

      success_result.merge("recovered_after_retry" => true)
    when "always_fail"
      raise PermanentError, "Downstream service rejected the request"
    when "invalid_payload"
      raise PermanentError, "Payload failed downstream validation"
    else
      raise PermanentError, "Unsupported simulation mode"
    end
  end

  private

  attr_reader :processing_request

  def success_result
    {
      "message" => "Request processed successfully",
      "echo" => processing_request.payload,
      "processed_at" => Time.current.iso8601
    }
  end
end
