defmodule Plausible.Purge do
  @moduledoc """
  Deletes data from a site.

  Stats are stored on Clickhouse, and unlike other databases data deletion is
  done asynchronously.

  - [Clickhouse `ALTER TABLE ... DELETE` Statement](https://clickhouse.com/docs/en/sql-reference/statements/alter/delete)
  - [Synchronicity of `ALTER` Queries](https://clickhouse.com/docs/en/sql-reference/statements/alter/#synchronicity-of-alter-queries)
  """

  @doc """
  Deletes a site and all associated stats.
  """
  @spec delete_site!(Plausible.Site.t()) :: :ok
  def delete_site!(site) do
    delete_native_stats!(site)
    delete_imported_stats!(site)
    Plausible.Repo.delete!(site)

    :ok
  end

  @spec delete_imported_stats!(Plausible.Site.t()) :: :ok
  @doc """
  Deletes imported stats from Google Analytics, and clears the
  `stats_start_date` field.
  """
  def delete_imported_stats!(site) do
    Enum.each(Plausible.Imported.tables(), fn table ->
      sql = "ALTER TABLE #{table} DELETE WHERE site_id = ?"
      Ecto.Adapters.SQL.query!(Plausible.ClickhouseRepo, sql, [site.id])
    end)

    clear_stats_start_date!(site)

    :ok
  end

  @spec delete_native_stats!(Plausible.Site.t()) :: :ok
  @doc """
  Deletes native stats for a site, and clears the `stats_start_date` field.
  """
  def delete_native_stats!(site) do
    events_sql = "ALTER TABLE events DELETE WHERE domain = ?"
    sessions_sql = "ALTER TABLE sessions DELETE WHERE domain = ?"
    Ecto.Adapters.SQL.query!(Plausible.ClickhouseRepo, events_sql, [site.domain])
    Ecto.Adapters.SQL.query!(Plausible.ClickhouseRepo, sessions_sql, [site.domain])

    clear_stats_start_date!(site)

    :ok
  end

  defp clear_stats_start_date!(site) do
    site
    |> Ecto.Changeset.change(stats_start_date: nil)
    |> Plausible.Repo.update!()
  end
end
