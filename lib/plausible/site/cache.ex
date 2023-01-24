defmodule Plausible.Site.Cache do
  @moduledoc """
  A "sites by domain" caching interface.

  Serves as a thin wrapper around Cachex, but the underlying
  implementation can be transparently swapped.

  Even though the Cachex process is started, cache access is disabled
  during tests via the `:sites_by_domain_cache_enabled` application env key.
  This can be overridden on case by case basis, using the child specs options.

  When Cache is disabled via application env, the `get/1` function
  falls back to pure database lookups. This should help with introducing
  cached lookups in existing code, so that no existing tests should break.

  To differentiate cached Site structs from those retrieved directly from the
  database, a virtual schema field `from_cache?: true` is set.
  This indicates the `Plausible.Site` struct is incomplete in comparison to its
  database counterpart -- to spare bandwidth and query execution time,
  only selected database columns are retrieved and cached.

  There are two modes of refreshing the cache: `:all` and `:updated_recently`.

    * `:all` means querying the database for all Site entries and should be done
      periodically (via `Cache.Warmer`). All stale Cache entries are cleared
      upon persisting the new batch.

    * `:updated_recently` attempts to re-query sites updated within the last
      15 minutes only, to account for most recent changes. This refresh
      is lighter on the database and is meant to be executed more frequently
      (via `Cache.Warmer.RecentlyUpdated`).

  Refreshing the cache emits telemetry event defined as per `telemetry_event_refresh/2`.

  The `@cached_schema_fields` attribute defines the list of DB columns
  queried on each cache refresh.

  Also see tests for more comprehensive examples.
  """
  require Logger

  import Ecto.Query

  alias Plausible.Site

  @cache_name :sites_by_domain
  @modes [:all, :updated_recently]

  @cached_schema_fields ~w(
     id
     domain
     ingest_rate_limit_scale_seconds
     ingest_rate_limit_threshold
   )a

  @type t() :: Site.t()

  @spec name() :: atom()
  def name(), do: @cache_name

  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    cache_name = Keyword.get(opts, :cache_name, @cache_name)
    child_id = Keyword.get(opts, :child_id, :cachex_sites)

    Supervisor.child_spec(
      {Cachex, name: cache_name, limit: nil, stats: true},
      id: child_id
    )
  end

  @spec ready?(atom()) :: boolean
  def ready?(cache_name \\ @cache_name) do
    case size(cache_name) do
      n when n > 0 ->
        true

      0 ->
        Plausible.Repo.aggregate(Site, :count) == 0
    end
  end

  @spec refresh_all(Keyword.t()) :: :ok
  def refresh_all(opts \\ []) do
    sites_by_domain_query =
      from s in Site,
        select: {
          s.domain,
          %{struct(s, ^@cached_schema_fields) | from_cache?: true}
        }

    refresh(
      :all,
      sites_by_domain_query,
      Keyword.put(opts, :delete_stale_items?, true)
    )
  end

  @spec refresh_updated_recently(Keyword.t()) :: :ok
  def refresh_updated_recently(opts \\ []) do
    recently_updated_sites_query =
      from s in Site,
        order_by: [asc: s.updated_at],
        where: s.updated_at > ago(^15, "minute"),
        select: {
          s.domain,
          %{struct(s, ^@cached_schema_fields) | from_cache?: true}
        }

    refresh(
      :updated_recently,
      recently_updated_sites_query,
      Keyword.put(opts, :delete_stale_items?, false)
    )
  end

  @spec merge(new_items :: [Site.t()], opts :: Keyword.t()) :: :ok
  def merge(new_items, opts \\ [])
  def merge([], _), do: :ok

  def merge(new_items, opts) do
    cache_name = Keyword.get(opts, :cache_name, @cache_name)
    true = Cachex.put_many!(cache_name, new_items)

    if Keyword.get(opts, :delete_stale_items?, true) do
      {:ok, old_keys} = Cachex.keys(cache_name)

      new = MapSet.new(Enum.into(new_items, [], fn {k, _} -> k end))
      old = MapSet.new(old_keys)

      old
      |> MapSet.difference(new)
      |> Enum.each(fn k ->
        Cachex.del(cache_name, k)
      end)
    end

    :ok
  end

  @spec size() :: non_neg_integer()
  def size(cache_name \\ @cache_name) do
    {:ok, size} = Cachex.size(cache_name)
    size
  end

  @spec hit_rate() :: number()
  def hit_rate(cache_name \\ @cache_name) do
    {:ok, stats} = Cachex.stats(cache_name)
    Map.get(stats, :hit_rate, 0)
  end

  @spec get(String.t(), Keyword.t()) :: t() | nil
  def get(domain, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, @cache_name)
    force? = Keyword.get(opts, :force?, false)

    if enabled?() or force? do
      case Cachex.get(cache_name, domain) do
        {:ok, nil} ->
          nil

        {:ok, site} ->
          site

        {:error, e} ->
          Logger.error(
            "Error retrieving '#{domain}' from '#{inspect(cache_name)}': #{inspect(e)}"
          )

          nil
      end
    else
      Plausible.Sites.get_by_domain(domain)
    end
  end

  @spec telemetry_event_refresh(atom(), atom()) :: list(atom())
  def telemetry_event_refresh(cache_name \\ @cache_name, mode) when mode in @modes do
    [:plausible, :cache, cache_name, :refresh, mode]
  end

  def enabled?() do
    Application.fetch_env!(:plausible, :sites_by_domain_cache_enabled) == true
  end

  defp refresh(mode, query, opts) when mode in @modes do
    cache_name = Keyword.get(opts, :cache_name, @cache_name)

    measure_duration(telemetry_event_refresh(cache_name, mode), fn ->
      sites_by_domain = Plausible.Repo.all(query)
      :ok = merge(sites_by_domain, opts)
    end)

    :ok
  end

  defp measure_duration(event, fun) when is_function(fun, 0) do
    {duration, result} = time_it(fun)
    :telemetry.execute(event, %{duration: duration}, %{})
    result
  end

  defp time_it(fun) do
    start = System.monotonic_time()
    result = fun.()
    stop = System.monotonic_time()
    {stop - start, result}
  end
end
