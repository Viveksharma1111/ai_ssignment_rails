class AddProcessingRequestConstraints < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :processing_requests,
      "status IN ('queued', 'processing', 'completed', 'failed', 'canceled')",
      name: "processing_requests_valid_status"

    add_check_constraint :processing_requests,
      "simulation_mode IN ('success', 'fail_once', 'always_fail', 'invalid_payload', 'slow_success')",
      name: "processing_requests_valid_simulation_mode"

    add_check_constraint :processing_requests,
      "attempts_count >= 0",
      name: "processing_requests_attempts_non_negative"

    add_check_constraint :processing_requests,
      "max_retries >= 0",
      name: "processing_requests_max_retries_non_negative"
  end
end
