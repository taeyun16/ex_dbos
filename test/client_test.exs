defmodule ExDbos.ClientTest do
  use ExUnit.Case, async: true

  alias ExDbos.Client

  defmodule RepoStub do
    @moduledoc false
  end

  test "builds client with defaults" do
    client = Client.new(repo: RepoStub)

    assert client.repo == RepoStub
    assert client.system_schema == "dbos"
    assert client.idempotency_schema == "public"
    assert client.idempotency_table == "control_api_idempotency"
    assert client.compat_module == ExDbos.Compat.V2_11
    assert client.idempotency_module == ExDbos.Idempotency
    assert client.sql_module == Ecto.Adapters.SQL
  end

  test "builds qualified tables" do
    client = Client.new(repo: RepoStub)

    assert Client.system_table(client, "workflow_status") == ~s("dbos"."workflow_status")
    assert Client.idempotency_table(client) == ~s("public"."control_api_idempotency")
  end
end
