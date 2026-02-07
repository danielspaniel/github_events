class CreateGithubEvents < ActiveRecord::Migration[8.1]
  def change
    # --- Actors (enriched from GitHub Users API) ---
    create_table :actors do |t|
      t.bigint :github_id, null: false
      t.string :login
      t.string :display_login
      t.string :avatar_url
      t.string :url
      t.string :etag
      t.jsonb :data, default: {}, null: false

      t.timestamps
    end

    add_index :actors, :github_id, unique: true

    # --- Repositories (enriched from GitHub Repos API) ---
    create_table :repositories do |t|
      t.bigint :github_id, null: false
      t.string :name
      t.string :url
      t.string :etag
      t.jsonb :data, default: {}, null: false

      t.timestamps
    end

    add_index :repositories, :github_id, unique: true

    # --- GitHub Events ---
    create_table :github_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false

      t.bigint :repository_identifier, null: false
      t.bigint :push_identifier, null: false
      t.string :ref, null: false
      t.string :head, null: false
      t.string :before, null: false

      t.references :actor, foreign_key: { to_table: :actors }
      t.references :repository, foreign_key: { to_table: :repositories }

      t.boolean :public
      t.datetime :github_created_at

      t.jsonb :data, null: false, default: {}

      t.timestamps
    end

    add_index :github_events, :event_id, unique: true
    add_index :github_events, :github_created_at
  end
end
