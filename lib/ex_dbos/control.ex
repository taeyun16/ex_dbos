defmodule ExDbos.Control do
  @moduledoc """
  Control operations for DBOS workflows.
  """

  alias ExDbos.Client

  @type control_result :: {:ok, map()} | {:error, term()}

  @spec health(Client.t()) :: control_result
  def health(client) do
    case compat_module(client).health(client) do
      :ok -> {:ok, %{"status" => "ok"}}
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @spec cancel_workflow(Client.t(), String.t(), String.t(), keyword()) :: control_result
  def cancel_workflow(client, workflow_id, request_key, opts \\ []) do
    client
    |> idempotency_module(client).with_idempotency(
      "cancel",
      workflow_id,
      request_key,
      opts,
      fn ->
        compat_module(client).cancel_workflow(client, workflow_id)
      end
    )
    |> normalize_result()
  end

  @spec resume_workflow(Client.t(), String.t(), String.t(), keyword()) :: control_result
  def resume_workflow(client, workflow_id, request_key, opts \\ []) do
    client
    |> idempotency_module(client).with_idempotency(
      "resume",
      workflow_id,
      request_key,
      opts,
      fn ->
        compat_module(client).resume_workflow(client, workflow_id)
      end
    )
    |> normalize_result()
  end

  @spec fork_workflow(Client.t(), String.t(), map(), String.t(), keyword()) :: control_result
  def fork_workflow(client, workflow_id, params, request_key, opts \\ []) when is_map(params) do
    start_step =
      normalize_start_step(Map.get(params, "start_step", Map.get(params, :start_step, 0)))

    normalized = normalize_fork_params(params)

    client
    |> idempotency_module(client).with_idempotency(
      "fork",
      workflow_id,
      request_key,
      opts,
      fn ->
        compat_module(client).fork_workflow(client, workflow_id, start_step, normalized)
      end
    )
    |> normalize_result()
  end

  defp compat_module(%Client{compat_module: module}), do: module
  defp idempotency_module(%Client{idempotency_module: module}), do: module

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
      "new_workflow_id" => Map.get(params, "new_workflow_id") || Map.get(params, :new_workflow_id),
      "application_version" => Map.get(params, "application_version") || Map.get(params, :application_version)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_result({:ok, payload}) when is_map(payload), do: {:ok, payload}
  defp normalize_result({:ok, payload}), do: {:ok, %{"result" => payload}}
  defp normalize_result({:error, reason}), do: {:error, normalize_error(reason)}

  defp normalize_error(%{postgres: _} = error), do: %{status: 500, body: %{"error" => inspect(error)}}

  defp normalize_error(%{status: _status, body: _body} = error), do: error
  defp normalize_error(reason), do: %{status: 500, body: %{"error" => inspect(reason)}}
end
