require "test_helper"

class ProcessingRequestTest < ActiveSupport::TestCase
  test "build_fingerprint is stable for hash key order" do
    left = { "amount" => 10, "customer" => { "id" => "1", "name" => "A" } }
    right = { "customer" => { "name" => "A", "id" => "1" }, "amount" => 10 }

    assert_equal ProcessingRequest.build_fingerprint(left), ProcessingRequest.build_fingerprint(right)
  end

  test "cancel refuses completed requests" do
    request = ProcessingRequest.create!(
      idempotency_key: "done-1",
      request_fingerprint: ProcessingRequest.build_fingerprint({ "a" => 1 }),
      payload: { "a" => 1 },
      status: "completed",
      simulation_mode: "success"
    )

    assert_not request.cancel!
  end

  test "only one concurrent worker can begin processing" do
    request = ProcessingRequest.create!(
      idempotency_key: "concurrency-1",
      request_fingerprint: ProcessingRequest.build_fingerprint({ "a" => 1 }),
      payload: { "a" => 1 },
      simulation_mode: "success"
    )

    results = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          request.reload.begin_processing!
        end
      end
    end.map(&:value)

    assert_equal 1, results.count(true)
    assert_equal 1, results.count(false)
    assert_equal "processing", request.reload.status
    assert_equal 1, request.attempts_count
  end
end
