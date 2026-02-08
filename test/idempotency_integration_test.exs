defmodule ExDbos.Test.IntegrationRepo do
  use Ecto.Repo,
    otp_app: :ex_dbos,
    adapter: Ecto.Adapters.Postgres
end

defmodule ExDbos.IdempotencyIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias ExDbos.Client
  alias ExDbos.Idempotency
  alias ExDbos.Test.IntegrationRepo

  @moduletag :integration

  setup_all do
    database_url = System.get_env("EX_DBOS_TEST_DATABASE_URL")

    if !database_url do
      raise """
      EX_DBOS_TEST_DATABASE_URL is required for integration tests.
      Example:
        EX_DBOS_RUN_INTEGRATION=1 EX_DBOS_TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/ex_dbos_test mix test --include integration
      """
    end

    Application.put_env(:ex_dbos, IntegrationRepo,
      url: database_url,
      pool: Sandbox,
      pool_size: 5
    )

    {:ok, _pid} = start_supervised(IntegrationRepo)
    :ok = Sandbox.mode(IntegrationRepo, :manual)

    :ok
  end

  setup do
    :ok = Sandbox.checkout(IntegrationRepo)

    client =
      Client.new(
        repo: IntegrationRepo,
        idempotency_table: "control_api_idempotency_it_#{System.unique_integer([:positive])}"
      )

    {:ok, client: client}
  end

  test "with_idempotency persists and replays through real DB transaction", %{client: client} do
    assert {:ok, %{"ok" => true, "idempotency_replayed" => false}} =
             Idempotency.with_idempotency(client, "cancel", "wf-it-1", "it-key-1", [], fn ->
               {:ok, %{"ok" => true}}
             end)

    assert {:ok, %{"ok" => true, "idempotency_replayed" => true}} =
             Idempotency.with_idempotency(client, "cancel", "wf-it-1", "it-key-1", [], fn ->
               flunk("operation should not execute on replay")
             end)
  end

  test "with_idempotency returns conflict for key reuse on different action", %{client: client} do
    assert {:ok, _} =
             Idempotency.with_idempotency(client, "cancel", "wf-it-2", "it-key-2", [], fn ->
               {:ok, %{"ok" => true}}
             end)

    assert {:error, %{status: 409, body: %{"error" => message}}} =
             Idempotency.with_idempotency(client, "resume", "wf-it-2", "it-key-2", [], fn ->
               {:ok, %{"ok" => true}}
             end)

    assert message =~ "different action/workflow"
  end
end
