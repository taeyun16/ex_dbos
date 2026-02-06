defmodule Repo.Migrations.CreateControlApiIdempotency do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS public.control_api_idempotency (
      request_key TEXT PRIMARY KEY,
      action TEXT NOT NULL,
      workflow_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('in_progress', 'succeeded', 'failed')),
      response_json JSONB,
      error_message TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS control_api_idempotency_action_workflow_idx
      ON public.control_api_idempotency (action, workflow_id)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS control_api_idempotency_action_workflow_idx")
    execute("DROP TABLE IF EXISTS public.control_api_idempotency")
  end
end
