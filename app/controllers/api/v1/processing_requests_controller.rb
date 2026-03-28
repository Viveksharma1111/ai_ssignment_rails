module Api
  module V1
    class ProcessingRequestsController < ActionController::API
      class IdempotencyConflictError < StandardError
        attr_reader :processing_request

        def initialize(processing_request)
          @processing_request = processing_request
          super()
        end
      end

      rescue_from ActionController::ParameterMissing, with: :render_bad_request

      def create
        idempotency_key = request.headers["Idempotency-Key"].to_s.strip
        return render json: { error: "Idempotency-Key header is required" }, status: :bad_request if idempotency_key.blank?

        payload = params.require(:payload).permit!.to_h
        simulation_mode = params[:simulation_mode].presence || "success"
        max_retries = parse_max_retries(params[:max_retries])

        processing_request = build_request(idempotency_key, payload, simulation_mode, max_retries)

        if processing_request.new_record?
          processing_request.save!
          ProcessRequestJob.perform_async(processing_request.id)
          render json: serialize(processing_request), status: :accepted
        else
          render json: serialize(processing_request), status: :ok
        end
      rescue ActiveRecord::RecordNotUnique
        existing_request = ProcessingRequest.find_by!(idempotency_key: idempotency_key)
        return render_conflict(existing_request) unless existing_request.duplicate_payload?(payload)

        render json: serialize(existing_request), status: :ok
      rescue IdempotencyConflictError => e
        render_conflict(e.processing_request)
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :bad_request
      end

      def show
        processing_request = ProcessingRequest.find(params[:id])
        render json: serialize(processing_request)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Request not found" }, status: :not_found
      end

      def cancel
        processing_request = ProcessingRequest.find(params[:id])

        if processing_request.cancel!
          render json: serialize(processing_request.reload), status: :accepted
        else
          render json: serialize(processing_request), status: :conflict
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Request not found" }, status: :not_found
      end

      private

      def build_request(idempotency_key, payload, simulation_mode, max_retries)
        fingerprint = ProcessingRequest.build_fingerprint(payload)
        existing_request = ProcessingRequest.find_by(idempotency_key: idempotency_key)

        if existing_request
          raise IdempotencyConflictError.new(existing_request) unless existing_request.duplicate_payload?(payload)

          return existing_request
        end

        ProcessingRequest.new(
          idempotency_key: idempotency_key,
          request_fingerprint: fingerprint,
          payload: payload,
          simulation_mode: simulation_mode,
          max_retries: max_retries
        )
      end

      def render_bad_request(exception)
        render json: { error: exception.message }, status: :bad_request
      end

      def parse_max_retries(raw_value)
        return 3 if raw_value.blank?

        Integer(raw_value)
      rescue ArgumentError, TypeError
        raise ActiveRecord::RecordInvalid.new(
          ProcessingRequest.new.tap { |record| record.errors.add(:max_retries, "must be an integer") }
        )
      end

      def render_conflict(existing_request)
        render json: {
          error: "Idempotency-Key has already been used with a different payload",
          request: serialize(existing_request)
        }, status: :conflict
      end

      def serialize(processing_request)
        {
          id: processing_request.id,
          idempotency_key: processing_request.idempotency_key,
          status: processing_request.status,
          simulation_mode: processing_request.simulation_mode,
          attempts_count: processing_request.attempts_count,
          max_retries: processing_request.max_retries,
          payload: processing_request.payload,
          result: processing_request.result,
          last_error: processing_request.last_error,
          created_at: processing_request.created_at,
          started_at: processing_request.started_at,
          completed_at: processing_request.completed_at,
          canceled_at: processing_request.canceled_at
        }
      end
    end
  end
end
