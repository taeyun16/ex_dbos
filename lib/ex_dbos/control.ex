defmodule ExDbos.Control do
  @moduledoc """
  Control operations for DBOS workflows.
  """

  alias ExDbos.{Client, Compat.V2_11, Idempotency}

  @type control_result :: {:ok, map()} | {:error, term()}

  @spec health(Client.t()) :: control_result
  def health(client) do
    case V2_11.health(client) do
      :ok -> {:ok, %{"status" => "ok"}}
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @spec cancel_workflow(Client.t(), String.t(), String.t(), keyword()) :: control_result
  def cancel_workflow(client, workflow_id, request_key, opts \\ []) do
    Idempotency.with_idempotency(client, "cancel", workflow_id, request_key, opts, fn ->
      V2_11.cancel_workflow(client, workflow_id)
    end)
    |> normalize_result()
  end

  @spec resume_workflow(Client.t(), String.t(), String.t(), keyword()) :: control_result
  def resume_workflow(client, workflow_id, request_key, opts \\ []) do
    Idempotency.with_idempotency(client, "resume", workflow_id, request_key, opts, fn ->
      V2_11.resume_workflow(client, workflow_id)
    end)
    |> normalize_result()
  end

  @spec fork_workflow(Client.t(), String.t(), map(), String.t(), keyword()) :: control_result
  def fork_workflow(client, workflow_id, params, request_key, opts \\ []) when is_map(params) do
    start_step =
      normalize_start_step(Map.get(params, "start_step", Map.get(params, :start_step, 0)))

    normalized = normalize_fork_params(params)

    Idempotency.with_idempotency(client, "fork", workflow_id, request_key, opts, fn ->
      V2_11.fork_workflow(client, workflow_id, start_step, normalized)
    end)
    |> normalize_result()
  end

  defp normalize_start_step(value) when is_integer(value) and value >= 0, do: value

  defp normalize_start_step(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp normalize_start_step(_), do: 0

  defp normalize_fork_params(params) do
    %{
      "new_workflow_id" =>
        Map.get(params, "new_workflow_id") || Map.get(params, :new_workflow_id),
      "application_version" =>
        Map.get(params, "application_version") || Map.get(params, :application_version)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_result({:ok, payload}) when is_map(payload), do: {:ok, payload}
  defp normalize_result({:ok, payload}), do: {:ok, %{"result" => payload}}
  defp normalize_result({:error, reason}), do: {:error, normalize_error(reason)}

  defp normalize_error(%{postgres: _} = error),
    do: %{status: 500, body: %{"error" => inspect(error)}}

  defp normalize_error(%{status: _status, body: _body} = error), do: error
  defp normalize_error(reason), do: %{status: 500, body: %{"error" => inspect(reason)}}
end
