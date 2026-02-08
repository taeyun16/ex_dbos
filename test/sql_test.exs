defmodule ExDbos.SQLTest do
  use ExUnit.Case, async: true

  alias ExDbos.SQL

  test "quotes valid identifiers" do
    assert SQL.identifier!("dbos", "schema") == ~s("dbos")
    assert SQL.qualified_table!("dbos", "workflow_status") == ~s("dbos"."workflow_status")
  end

  test "rejects unsafe identifiers" do
    assert_raise ArgumentError, fn ->
      SQL.identifier!("dbos;drop", "schema")
    end
  end

  test "provides epoch milliseconds fragment" do
    assert SQL.now_epoch_ms_fragment() == "(extract(epoch from now()) * 1000)::bigint"
  end
end
