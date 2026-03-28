class ProcessRequestJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: false

  def perform(processing_request_id)
    processing_request = ProcessingRequest.find(processing_request_id)
    return if processing_request.canceled? || processing_request.completed?
    return unless processing_request.begin_processing!

    Rails.logger.info(log_data(processing_request, "started"))

    result = DownstreamProcessor.call(processing_request)
    completed = processing_request.mark_completed!(result)

    Rails.logger.info(log_data(processing_request.reload, completed ? "completed" : "discarded_after_cancel"))
  rescue DownstreamProcessor::TransientError => e
    handle_transient_failure(processing_request, e)
  rescue DownstreamProcessor::PermanentError => e
    if processing_request.reload.canceled?
      Rails.logger.info(log_data(processing_request, "canceled"))
    else
      processing_request.mark_failed!(e.message)
      Rails.logger.warn(log_data(processing_request.reload, "failed", error: e.message))
    end
  end

  private

  def handle_transient_failure(processing_request, error)
    if processing_request.reload.canceled?
      Rails.logger.info(log_data(processing_request, "canceled"))
      return
    end

    processing_request.mark_failed!(error.message)

    if processing_request.can_retry?
      Rails.logger.warn(log_data(processing_request.reload, "retrying", error: error.message))
      self.class.perform_in(retry_delay(processing_request.attempts_count), processing_request.id)
    else
      Rails.logger.error(log_data(processing_request.reload, "exhausted", error: error.message))
    end
  end

  def retry_delay(attempt)
    attempt.seconds
  end

  def log_data(processing_request, event, extra = {})
    {
      event: "processing_request.#{event}",
      request_id: processing_request.id,
      idempotency_key: processing_request.idempotency_key,
      status: processing_request.status,
      attempts_count: processing_request.attempts_count
    }.merge(extra)
  end
end
