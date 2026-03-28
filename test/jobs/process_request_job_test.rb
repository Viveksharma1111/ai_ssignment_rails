require "test_helper"

class ProcessRequestJobTest < ActiveSupport::TestCase
  test "retries transient failures without duplicating the record" do
    request = ProcessingRequest.create!(
      idempotency_key: "retry-1",
      request_fingerprint: ProcessingRequest.build_fingerprint({ "a" => 1 }),
      payload: { "a" => 1 },
      simulation_mode: "fail_once"
    )

    assert_difference -> { ProcessRequestJob.jobs.size }, 1 do
      ProcessRequestJob.new.perform(request.id)
    end

    request.reload
    assert_equal "failed", request.status
    assert_equal 1, request.attempts_count

    scheduled_job = ProcessRequestJob.jobs.last
    ProcessRequestJob.new.perform(*scheduled_job["args"])

    request.reload
    assert_equal "completed", request.status
    assert_equal 2, request.attempts_count
    assert_equal true, request.result["recovered_after_retry"]
  end

  test "does not overwrite canceled requests with success" do
    request = ProcessingRequest.create!(
      idempotency_key: "cancel-1",
      request_fingerprint: ProcessingRequest.build_fingerprint({ "a" => 1 }),
      payload: { "a" => 1 },
      simulation_mode: "slow_success"
    )

    worker = Thread.new { ProcessRequestJob.new.perform(request.id) }
    sleep 0.01
    request.reload.cancel!
    worker.join

    request.reload
    assert_equal "canceled", request.status
    assert_equal({}, request.result)
  end

  test "does not retry permanent failures" do
    request = ProcessingRequest.create!(
      idempotency_key: "permanent-1",
      request_fingerprint: ProcessingRequest.build_fingerprint({ "a" => 1 }),
      payload: { "a" => 1 },
      simulation_mode: "always_fail"
    )

    assert_no_difference -> { ProcessRequestJob.jobs.size } do
      ProcessRequestJob.new.perform(request.id)
    end

    request.reload
    assert_equal "failed", request.status
    assert_equal 1, request.attempts_count
    assert_match(/rejected/, request.last_error)
  end
end
