class ProcessingRequest < ApplicationRecord
  TRANSIENT_FAILURES = %w[fail_once].freeze
  PERMANENT_FAILURES = %w[always_fail invalid_payload].freeze
  SIMULATION_MODES = %w[success fail_once always_fail invalid_payload slow_success].freeze
  TERMINAL_STATUSES = %w[completed failed canceled].freeze

  validates :idempotency_key, presence: true, uniqueness: true
  validates :request_fingerprint, presence: true
  validates :status, presence: true, inclusion: { in: %w[queued processing completed failed canceled] }
  validates :simulation_mode, inclusion: { in: SIMULATION_MODES }
  validates :attempts_count, numericality: { greater_than_or_equal_to: 0 }
  validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :payload_must_be_an_object

  scope :active, -> { where(status: %w[queued processing]) }

  def self.build_fingerprint(payload)
    Digest::SHA256.hexdigest(JSON.generate(normalize(payload)))
  end

  def self.normalize(value)
    case value
    when Hash
      value.deep_stringify_keys.sort.to_h { |key, nested| [ key, normalize(nested) ] }
    when Array
      value.map { |item| normalize(item) }
    else
      value
    end
  end

  def duplicate_payload?(payload)
    request_fingerprint == self.class.build_fingerprint(payload)
  end

  def queued?
    status == "queued"
  end

  def processing?
    status == "processing"
  end

  def canceled?
    status == "canceled"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def can_retry?
    failed? && attempts_count < max_retries && !canceled?
  end

  def begin_processing!
    with_lock do
      return false if canceled? || completed?
      return false if processing?
      return false if failed? && attempts_count >= max_retries

      update!(
        status: "processing",
        attempts_count: attempts_count + 1,
        started_at: Time.current,
        completed_at: nil,
        result: {},
        last_error: nil
      )
    end

    true
  end

  def mark_completed!(result_payload)
    with_lock do
      return false if canceled?

      update!(
        status: "completed",
        result: result_payload,
        completed_at: Time.current,
        last_error: nil
      )
    end

    true
  end

  def mark_failed!(message)
    with_lock do
      update!(
        status: "failed",
        last_error: message,
        completed_at: Time.current
      )
    end
  end

  def cancel!
    with_lock do
      return false if completed?
      return false if canceled?

      update!(
        status: "canceled",
        canceled_at: Time.current,
        completed_at: Time.current
      )
    end

    true
  end

  private

  def payload_must_be_an_object
    errors.add(:payload, "must be a JSON object") unless payload.is_a?(Hash)
  end
end
