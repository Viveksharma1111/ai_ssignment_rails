# AI-Assisted Rails Assignment

This project implements a small Rails API for processing requests asynchronously with Sidekiq while handling duplicate submissions, retries, cancellations, downstream failures, and basic concurrency safety.

## What It Does

- Accepts requests through a REST API
- Requires an `Idempotency-Key` header for safe retries
- Persists each request and its current status in the database
- Processes work through a Sidekiq worker
- Prevents duplicate processing with a unique DB constraint and payload fingerprinting
- Supports cancellation before or during processing
- Distinguishes retryable failures from terminal failures

## API

### `POST /api/v1/requests`

Headers:

```text
Content-Type: application/json
Idempotency-Key: order-123
```

Body:

```json
{
  "payload": {
    "customer_id": "cust_42",
    "amount": 1500
  },
  "simulation_mode": "fail_once",
  "max_retries": 3
}
```

Supported `simulation_mode` values:

- `success`
- `fail_once`
- `always_fail`
- `invalid_payload`
- `slow_success`

Behavior:

- New request returns `202 Accepted`
- Same `Idempotency-Key` with same payload returns the existing record with `200 OK`
- Same `Idempotency-Key` with different payload returns `409 Conflict`
- Invalid input returns `400 Bad Request`

### `GET /api/v1/requests/:id`

Returns the current request state and any result or error details.

### `POST /api/v1/requests/:id/cancel`

Marks a queued or in-flight request as canceled. Completed requests return `409 Conflict`.

## Design Notes

- Idempotency is enforced in two layers: application lookup and a unique DB index on `idempotency_key`
- Database check constraints also enforce valid status values, retry counts, and simulation modes
- Payload fingerprinting detects misuse of the same idempotency key with a different request body
- `with_lock` guards state transitions so concurrent workers do not overwrite each other
- Retries are explicit and only happen for transient downstream errors
- Permanent failures are not retried
- If cancellation happens during a slow request, the worker checks again before completion and avoids writing a success result

## Assignment Mapping

- REST API endpoint: `POST /api/v1/requests`, `GET /api/v1/requests/:id`, `POST /api/v1/requests/:id/cancel`
- Background job: native Sidekiq worker `ProcessRequestJob`
- Data persisted with status: `processing_requests` table
- Duplicate handling: idempotency key plus payload fingerprint
- Retry logic without duplication: transient failure path only
- Downstream failure handling: permanent failures stop and store error details
- Concurrency/race conditions: unique index, locking, and concurrency tests
- Cancellation handling: queued and in-flight requests can be canceled
- Logging: structured lifecycle logs for start, retry, completion, failure, and cancel events

## Run It

```bash
bundle install
bin/rails db:prepare
redis-server
bin/rails server
```

In another terminal, run Sidekiq:

```bash
bundle exec sidekiq -C config/sidekiq.yml
```

## Run Tests

```bash
bin/rails test
```

## Postman Collection

Import [postman/ai_assesment_sidekiq_api.postman_collection.json](/Users/vivek/a_workspace/assesment_ai/ai_assesment/postman/ai_assesment_sidekiq_api.postman_collection.json) into Postman.

Default variables:

- `base_url = http://localhost:3000`
- `idempotency_key = order-123`
- `request_id` is captured automatically from the create request
