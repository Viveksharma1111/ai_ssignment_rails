# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_03_28_113000) do
  create_table "processing_requests", force: :cascade do |t|
    t.string "idempotency_key", null: false
    t.string "request_fingerprint", null: false
    t.string "status", default: "queued", null: false
    t.json "payload", default: {}, null: false
    t.json "result", default: {}, null: false
    t.string "simulation_mode", default: "success", null: false
    t.integer "attempts_count", default: 0, null: false
    t.integer "max_retries", default: 3, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "canceled_at"
    t.text "last_error"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_processing_requests_on_idempotency_key", unique: true
    t.index ["status"], name: "index_processing_requests_on_status"
    t.check_constraint "attempts_count >= 0", name: "processing_requests_attempts_non_negative"
    t.check_constraint "max_retries >= 0", name: "processing_requests_max_retries_non_negative"
    t.check_constraint "simulation_mode IN ('success', 'fail_once', 'always_fail', 'invalid_payload', 'slow_success')", name: "processing_requests_valid_simulation_mode"
    t.check_constraint "status IN ('queued', 'processing', 'completed', 'failed', 'canceled')", name: "processing_requests_valid_status"
  end
end
