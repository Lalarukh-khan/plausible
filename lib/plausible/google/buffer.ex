defmodule Plausible.Google.Buffer do
  @moduledoc """
  This GenServer inserts records into Clickhouse `imported_*` tables. Multiple buffers are
  automatically created for each table. Records are flushed when the table buffer reaches the
  maximum size, defined by `max_buffer_size/0`.
  """

  use GenServer
  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, nil)
  end

  def init(_opts) do
    {:ok, %{buffers: %{}}}
  end

  @spec insert_many(pid(), term(), [map()]) :: :ok
  @doc """
  Puts the given records into the table buffer.
  """
  def insert_many(pid, table_name, records) do
    GenServer.call(pid, {:insert_many, table_name, records})
  end

  @spec size(pid(), term()) :: non_neg_integer()
  @doc """
  Returns the total count of items in the given table buffer.
  """
  def size(pid, table_name) do
    GenServer.call(pid, {:get_size, table_name})
  end

  @spec flush(pid()) :: :ok
  @doc """
  Flushes all table buffers to Clickhouse.
  """
  def flush(pid, timeout \\ :infinity) do
    GenServer.call(pid, :flush_all_buffers, timeout)
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  def handle_call({:get_size, table_name}, _from, %{buffers: buffers} = state) do
    size =
      buffers
      |> Map.get(table_name, [])
      |> length()

    {:reply, size, state}
  end

  def handle_call({:insert_many, table_name, records}, _from, %{buffers: buffers} = state) do
    Logger.info("Import: Adding #{length(records)} to #{table_name} buffer")

    new_buffer = Map.get(buffers, table_name, []) ++ records
    new_state = put_in(state.buffers[table_name], new_buffer)

    if length(new_buffer) >= max_buffer_size() do
      {:reply, :ok, new_state, {:continue, {:flush, table_name}}}
    else
      {:reply, :ok, new_state}
    end
  end

  def handle_call(:flush_all_buffers, _from, state) do
    Enum.each(state.buffers, fn {table_name, records} ->
      flush_buffer(records, table_name)
    end)

    {:reply, :ok, put_in(state.buffers, %{})}
  end

  def handle_continue({:flush, table_name}, state) do
    flush_buffer(state.buffers[table_name], table_name)
    {:noreply, put_in(state.buffers[table_name], [])}
  end

  defp max_buffer_size do
    :plausible
    |> Application.get_env(:google)
    |> Keyword.fetch!(:max_buffer_size)
  end

  defp flush_buffer(records, table_name) do
    # Clickhouse does not recommend sending more than 1 INSERT operation per second, and this
    # sleep call slows down the flushing
    Process.sleep(1000)

    Logger.info("Import: Flushing #{length(records)} from #{table_name} buffer")
    Plausible.ClickhouseRepo.insert_all(table_name, records)
  end
end
