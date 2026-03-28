require "test_helper"

class Api::V1::ProcessingRequestsControllerTest < ActionDispatch::IntegrationTest
  test "creates a processing request" do
    assert_difference -> { ProcessRequestJob.jobs.size }, 1 do
      post "/api/v1/requests",
        params: { payload: { order_id: "ord_1" }, simulation_mode: "success" },
        as: :json,
        headers: { "Idempotency-Key" => "key-1" }
    end

    assert_response :accepted
    body = response.parsed_body
    assert_equal "queued", body["status"]
    assert_equal "key-1", body["idempotency_key"]
  end

  test "returns existing request for duplicate idempotent submission" do
    post "/api/v1/requests",
      params: { payload: { order_id: "ord_1" } },
      as: :json,
      headers: { "Idempotency-Key" => "key-duplicate" }

    assert_response :accepted

    assert_no_difference -> { ProcessRequestJob.jobs.size } do
      post "/api/v1/requests",
        params: { payload: { order_id: "ord_1" } },
        as: :json,
        headers: { "Idempotency-Key" => "key-duplicate" }
    end

    assert_response :ok
    assert_equal 1, ProcessingRequest.where(idempotency_key: "key-duplicate").count
  end

  test "rejects same idempotency key with different payload" do
    post "/api/v1/requests",
      params: { payload: { order_id: "ord_1" } },
      as: :json,
      headers: { "Idempotency-Key" => "key-conflict" }

    post "/api/v1/requests",
      params: { payload: { order_id: "ord_2" } },
      as: :json,
      headers: { "Idempotency-Key" => "key-conflict" }

    assert_response :conflict
  end

  test "requires an idempotency key" do
    post "/api/v1/requests", params: { payload: { order_id: "ord_1" } }, as: :json

    assert_response :bad_request
  end

  test "rejects invalid simulation mode" do
    post "/api/v1/requests",
      params: { payload: { order_id: "ord_1" }, simulation_mode: "wrong" },
      as: :json,
      headers: { "Idempotency-Key" => "key-invalid-mode" }

    assert_response :bad_request
    assert_match(/Simulation mode/i, response.parsed_body["error"])
  end

  test "rejects non integer max retries" do
    post "/api/v1/requests",
      params: { payload: { order_id: "ord_1" }, max_retries: "three" },
      as: :json,
      headers: { "Idempotency-Key" => "key-invalid-retries" }

    assert_response :bad_request
    assert_match(/Max retries/i, response.parsed_body["error"])
  end

  test "cancels a queued request" do
    post "/api/v1/requests",
      params: { payload: { order_id: "ord_1" } },
      as: :json,
      headers: { "Idempotency-Key" => "key-cancel" }

    request_id = response.parsed_body["id"]

    post "/api/v1/requests/#{request_id}/cancel", as: :json

    assert_response :accepted
    assert_equal "canceled", response.parsed_body["status"]
  end

  test "shows an existing request" do
    post "/api/v1/requests",
      params: { payload: { order_id: "ord_1" } },
      as: :json,
      headers: { "Idempotency-Key" => "key-show" }

    request_id = response.parsed_body["id"]

    get "/api/v1/requests/#{request_id}"

    assert_response :success
    assert_equal request_id, response.parsed_body["id"]
  end
end
