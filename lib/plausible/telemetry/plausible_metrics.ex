defmodule Plausible.PromEx.Plugins.PlausibleMetrics do
  @moduledoc """
  Custom PromEx plugin for instrumenting code within Plausible app.
  """
  use PromEx.Plugin
  alias Plausible.Site
  alias Plausible.Ingestion

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    otp_app = Keyword.fetch!(opts, :otp_app)

    metric_prefix =
      Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :plausible_metrics))

    [
      write_buffer_metrics(metric_prefix, poll_rate),
      cache_metrics(metric_prefix, poll_rate)
    ]
  end

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :plausible))

    Event.build(
      :plausible_internal_telemetry,
      [
        distribution(
          metric_prefix ++ [:cache_warmer, :sites, :refresh, :all],
          event_name: Site.Cache.telemetry_event_refresh(:all),
          reporter_options: [
            buckets: [500, 1000, 2000, 5000, 10_000]
          ],
          unit: {:native, :millisecond},
          measurement: :duration
        ),
        distribution(
          metric_prefix ++ [:cache_warmer, :sites, :refresh, :updated_recently],
          event_name: Site.Cache.telemetry_event_refresh(:updated_recently),
          reporter_options: [
            buckets: [500, 1000, 2000, 5000, 10_000]
          ],
          unit: {:native, :millisecond},
          measurement: :duration
        ),
        counter(
          metric_prefix ++ [:ingest, :events, :buffered, :total],
          event_name: Ingestion.Event.telemetry_event_buffered()
        ),
        counter(
          metric_prefix ++ [:ingest, :events, :dropped, :total],
          event_name: Ingestion.Event.telemetry_event_dropped(),
          tags: [:reason]
        )
      ]
    )
  end

  @doc """
  Add telemetry events for Session and Event write buffers
  """
  def execute_write_buffer_metrics do
    event_write_buffer_pid = GenServer.whereis(Plausible.Event.WriteBuffer)

    {:message_queue_len, events_message_queue_len} =
      if is_pid(event_write_buffer_pid),
        do: Process.info(event_write_buffer_pid, :message_queue_len),
        else: {:message_queue_len, 0}

    session_write_buffer_pid = GenServer.whereis(Plausible.Event.WriteBuffer)

    {:message_queue_len, sessions_message_queue_len} =
      if is_pid(session_write_buffer_pid),
        do: Process.info(session_write_buffer_pid, :message_queue_len),
        else: {:message_queue_len, 0}

    :telemetry.execute([:prom_ex, :plugin, :write_buffer_metrics, :events_message_queue_len], %{
      count: events_message_queue_len
    })

    :telemetry.execute([:prom_ex, :plugin, :write_buffer_metrics, :sessions_message_queue_len], %{
      count: sessions_message_queue_len
    })
  end

  @doc """
  Add telemetry events for Cachex user agents and sessions
  """
  def execute_cache_metrics do
    {:ok, user_agents_stats} = Cachex.stats(:user_agents)
    {:ok, sessions_stats} = Cachex.stats(:sessions)

    user_agents_hit_rate = Map.get(user_agents_stats, :hit_rate, 0.0)
    sessions_hit_rate = Map.get(sessions_stats, :hit_rate, 0.0)

    {:ok, user_agents_count} = Cachex.size(:user_agents)
    {:ok, sessions_count} = Cachex.size(:sessions)

    :telemetry.execute([:prom_ex, :plugin, :cachex, :user_agents], %{
      count: user_agents_count,
      hit_rate: user_agents_hit_rate
    })

    :telemetry.execute([:prom_ex, :plugin, :cachex, :sessions], %{
      count: sessions_count,
      hit_rate: sessions_hit_rate
    })

    :telemetry.execute([:prom_ex, :plugin, :cachex, :sites], %{
      count: Site.Cache.size(),
      hit_rate: Site.Cache.hit_rate()
    })
  end

  defp write_buffer_metrics(metric_prefix, poll_rate) do
    Polling.build(
      :write_buffer_metrics,
      poll_rate,
      {__MODULE__, :execute_write_buffer_metrics, []},
      [
        last_value(
          metric_prefix ++ [:events, :message_queue_len, :count],
          event_name: [:prom_ex, :plugin, :write_buffer_metrics, :events_message_queue_len],
          measurement: :count
        ),
        last_value(
          metric_prefix ++ [:sessions, :message_queue_len, :count],
          event_name: [:prom_ex, :plugin, :write_buffer_metrics, :sessions_message_queue_len],
          measurement: :count
        )
      ]
    )
  end

  defp cache_metrics(metric_prefix, poll_rate) do
    Polling.build(
      :cache_metrics,
      poll_rate,
      {__MODULE__, :execute_cache_metrics, []},
      [
        last_value(
          metric_prefix ++ [:cache, :sessions, :size],
          event_name: [:prom_ex, :plugin, :cachex, :sessions],
          measurement: :count
        ),
        last_value(
          metric_prefix ++ [:cache, :user_agents, :size],
          event_name: [:prom_ex, :plugin, :cachex, :user_agents],
          measurement: :count
        ),
        last_value(
          metric_prefix ++ [:cache, :user_agents, :hit_ratio],
          event_name: [:prom_ex, :plugin, :cachex, :user_agents],
          measurement: :hit_rate
        ),
        last_value(
          metric_prefix ++ [:cache, :sessions, :hit_ratio],
          event_name: [:prom_ex, :plugin, :cachex, :sessions],
          measurement: :hit_rate
        ),
        last_value(
          metric_prefix ++ [:cache, :sites, :size],
          event_name: [:prom_ex, :plugin, :cachex, :sites],
          measurement: :count
        ),
        last_value(
          metric_prefix ++ [:cache, :sites, :hit_ratio],
          event_name: [:prom_ex, :plugin, :cachex, :sites],
          measurement: :hit_rate
        )
      ]
    )
  end
end
