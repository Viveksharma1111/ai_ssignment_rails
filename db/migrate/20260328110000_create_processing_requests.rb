class CreateProcessingRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :processing_requests do |t|
      t.string :idempotency_key, null: false
      t.string :request_fingerprint, null: false
      t.string :status, null: false, default: "queued"
      t.json :payload, null: false, default: {}
      t.json :result, null: false, default: {}
      t.string :simulation_mode, null: false, default: "success"
      t.integer :attempts_count, null: false, default: 0
      t.integer :max_retries, null: false, default: 3
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :canceled_at
      t.text :last_error
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :processing_requests, :idempotency_key, unique: true
    add_index :processing_requests, :status
  end
end
