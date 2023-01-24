defmodule PlausibleWeb.Api.StatsController.MainGraphTest do
  use PlausibleWeb.ConnCase

  @user_id 123

  describe "GET /api/stats/main-graph - plot" do
    setup [:create_user, :log_in, :create_new_site, :add_imported_data]

    test "displays pageviews for the last 30 minutes in realtime graph", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: relative_time(minutes: -5))
      ])

      conn = get(conn, "/api/stats/#{site.domain}/main-graph?period=realtime&metric=pageviews")

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 30
      assert Enum.any?(plot, fn pageviews -> pageviews > 0 end)
    end

    test "displays visitors for a day", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-01 23:00:00])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=day&date=2021-01-01&metric=pageviews"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      zeroes = Stream.repeatedly(fn -> 0 end) |> Stream.take(22) |> Enum.into([])

      assert Enum.count(plot) == 24
      assert plot == [1] ++ zeroes ++ [1]
    end

    test "displays hourly stats in configured timezone", %{conn: conn, user: user} do
      # UTC+1
      site = insert(:site, domain: "tz-test.com", members: [user], timezone: "CET")

      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=day&date=2021-01-01&metric=visitors"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      zeroes = Stream.repeatedly(fn -> 0 end) |> Stream.take(22) |> Enum.into([])

      # Expecting pageview to show at 1am CET
      assert plot == [0, 1] ++ zeroes
    end

    test "displays visitors for a month", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-31 00:00:00])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&metric=visitors"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 1
      assert List.last(plot) == 1
      assert Enum.sum(plot) == 2
    end

    test "displays visitors for a month with imported data", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-31 00:00:00]),
        build(:imported_visitors, date: ~D[2021-01-01]),
        build(:imported_visitors, date: ~D[2021-01-31])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&with_imported=true"
        )

      assert %{"plot" => plot, "imported_source" => "Google Analytics"} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 2
      assert List.last(plot) == 2
      assert Enum.sum(plot) == 4
    end

    test "displays visitors for a month with imported data and filter", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00], pathname: "/pageA"),
        build(:pageview, timestamp: ~N[2021-01-31 00:00:00], pathname: "/pageA"),
        build(:imported_visitors, date: ~D[2021-01-01]),
        build(:imported_visitors, date: ~D[2021-01-31])
      ])

      filters = Jason.encode!(%{page: "/pageA"})

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&with_imported=true&filters=#{filters}"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 1
      assert List.last(plot) == 1
      assert Enum.sum(plot) == 2
    end

    test "displays visitors for 6 months with imported data", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-06-30 00:00:00]),
        build(:imported_visitors, date: ~D[2021-01-01]),
        build(:imported_visitors, date: ~D[2021-06-30])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=6mo&date=2021-06-30&with_imported=true"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 6
      assert List.first(plot) == 2
      assert List.last(plot) == 2
      assert Enum.sum(plot) == 4
    end

    test "displays visitors for 12 months with imported data", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-12-31 00:00:00]),
        build(:imported_visitors, date: ~D[2021-01-01]),
        build(:imported_visitors, date: ~D[2021-12-31])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=12mo&date=2021-12-31&with_imported=true"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 12
      assert List.first(plot) == 2
      assert List.last(plot) == 2
      assert Enum.sum(plot) == 4
    end

    test "displays visitors for calendar year with imported data", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-12-31 00:00:00]),
        build(:imported_visitors, date: ~D[2021-01-01]),
        build(:imported_visitors, date: ~D[2021-12-31])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=year&date=2021-12-31&with_imported=true"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 12
      assert List.first(plot) == 2
      assert List.last(plot) == 2
      assert Enum.sum(plot) == 4
    end

    test "displays visitors for all time with just native data", %{conn: conn, site: site} do
      use Plausible.Repo

      Repo.update_all(from(s in "sites", where: s.id == ^site.id),
        set: [stats_start_date: ~D[2020-01-01]]
      )

      populate_stats(site, [
        build(:pageview, timestamp: ~N[2020-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-12-31 00:00:00])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=all&with_imported=true"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert List.first(plot) == 1
      assert Enum.sum(plot) == 3
    end
  end

  describe "GET /api/stats/main-graph - default labels" do
    setup [:create_user, :log_in, :create_site]

    test "shows last 30 days", %{conn: conn, site: site} do
      conn = get(conn, "/api/stats/#{site.domain}/main-graph?period=30d&metric=visitors")
      assert %{"labels" => labels} = json_response(conn, 200)

      {:ok, first} = Timex.today() |> Timex.shift(days: -30) |> Timex.format("{ISOdate}")
      {:ok, last} = Timex.today() |> Timex.format("{ISOdate}")
      assert List.first(labels) == first
      assert List.last(labels) == last
    end

    test "shows last 7 days", %{conn: conn, site: site} do
      conn = get(conn, "/api/stats/#{site.domain}/main-graph?period=7d&metric=visitors")
      assert %{"labels" => labels} = json_response(conn, 200)

      {:ok, first} = Timex.today() |> Timex.shift(days: -6) |> Timex.format("{ISOdate}")
      {:ok, last} = Timex.today() |> Timex.format("{ISOdate}")
      assert List.first(labels) == first
      assert List.last(labels) == last
    end
  end

  describe "GET /api/stats/main-graph - pageviews plot" do
    setup [:create_user, :log_in, :create_new_site, :add_imported_data]

    test "displays pageviews for a month", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-31 00:00:00])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&metric=pageviews"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 2
      assert List.last(plot) == 1
    end

    test "displays pageviews for a month with imported data", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-31 00:00:00]),
        build(:imported_visitors, date: ~D[2021-01-01]),
        build(:imported_visitors, date: ~D[2021-01-31])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&metric=pageviews&with_imported=true"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 2
      assert List.last(plot) == 2
      assert Enum.sum(plot) == 4
    end
  end

  describe "GET /api/stats/main-graph - bounce_rate plot" do
    setup [:create_user, :log_in, :create_new_site, :add_imported_data]

    test "displays bounce_rate for a month", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-03 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-03 00:10:00]),
        build(:pageview, timestamp: ~N[2021-01-31 00:00:00])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&metric=bounce_rate"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 0
      assert List.last(plot) == 100
    end

    test "displays bounce rate for a month with imported data", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-31 00:00:00]),
        build(:imported_visitors, visits: 1, bounces: 0, date: ~D[2021-01-01]),
        build(:imported_visitors, visits: 1, bounces: 1, date: ~D[2021-01-31])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&metric=bounce_rate&with_imported=true"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 50
      assert List.last(plot) == 100
    end
  end

  describe "GET /api/stats/main-graph - visit_duration plot" do
    setup [:create_user, :log_in, :create_new_site, :add_imported_data]

    test "displays visit_duration for a month", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview,
          pathname: "/page3",
          user_id: @user_id,
          timestamp: ~N[2021-01-31 00:10:00]
        ),
        build(:pageview,
          pathname: "/page2",
          user_id: @user_id,
          timestamp: ~N[2021-01-31 00:15:00]
        )
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&metric=visit_duration"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 0
      assert List.last(plot) == 300
    end

    test "displays visit_duration for a month with imported data", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, user_id: @user_id, timestamp: ~N[2021-01-01 00:10:00]),
        build(:pageview, user_id: @user_id, timestamp: ~N[2021-01-01 00:15:00]),
        build(:imported_visitors, visits: 1, visit_duration: 100, date: ~D[2021-01-01])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&metric=visit_duration&with_imported=true"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 31
      assert List.first(plot) == 200
    end
  end

  describe "GET /api/stats/main-graph - varying intervals" do
    setup [:create_user, :log_in, :create_new_site]

    test "displays visitors for 6mo on a day scale", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-15 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-15 00:00:00]),
        build(:pageview, timestamp: ~N[2021-02-15 00:00:00]),
        build(:pageview, timestamp: ~N[2021-06-30 01:00:00])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=6mo&date=2021-06-01&metric=visitors&interval=date"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 181
      assert List.first(plot) == 1
      assert Enum.at(plot, 14) == 2
      assert Enum.at(plot, 45) == 1
      assert List.last(plot) == 1
    end

    test "displays visitors for a custom period on a monthly scale", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-15 00:00:00]),
        build(:pageview, timestamp: ~N[2021-02-15 00:00:00]),
        build(:pageview, timestamp: ~N[2021-06-01 00:00:00])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=custom&from=2021-01-01&to=2021-06-30&metric=visitors&interval=month"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 6
      assert List.first(plot) == 2
      assert Enum.at(plot, 1) == 1
      assert List.last(plot) == 1
    end

    test "returns error when requesting an interval longer than the time period", %{
      conn: conn,
      site: site
    } do
      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=day&date=2021-01-01&metric=visitors&interval=month"
        )

      assert %{
               "error" =>
                 "Invalid combination of interval and period. Interval must be smaller than the selected period, e.g. `period=day,interval=minute`"
             } == json_response(conn, 400)
    end

    test "returns error when the interval is not valid", %{
      conn: conn,
      site: site
    } do
      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=day&date=2021-01-01&metric=visitors&interval=biweekly"
        )

      assert %{
               "error" =>
                 "Invalid value for interval. Accepted values are: minute, hour, date, week, month"
             } == json_response(conn, 400)
    end

    test "displays visitors for a month on a weekly scale", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, timestamp: ~N[2021-01-01 00:00:00]),
        build(:pageview, timestamp: ~N[2021-01-01 00:15:01]),
        build(:pageview, timestamp: ~N[2021-01-05 00:15:02])
      ])

      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&date=2021-01-01&metric=visitors&interval=week"
        )

      assert %{"plot" => plot} = json_response(conn, 200)

      assert Enum.count(plot) == 5
      assert List.first(plot) == 2
      assert Enum.at(plot, 1) == 1
    end

    test "shows imperfect week-split month on week scale with full week indicators", %{
      conn: conn,
      site: site
    } do
      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&metric=visitors&interval=week&date=2021-09-01"
        )

      assert %{"labels" => labels, "full_intervals" => full_intervals} = json_response(conn, 200)

      assert labels == ["2021-09-01", "2021-09-06", "2021-09-13", "2021-09-20", "2021-09-27"]

      assert full_intervals == %{
               "2021-09-01" => false,
               "2021-09-06" => true,
               "2021-09-13" => true,
               "2021-09-20" => true,
               "2021-09-27" => false
             }
    end

    test "shows half-perfect week-split month on week scale with full week indicators", %{
      conn: conn,
      site: site
    } do
      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=month&metric=visitors&interval=week&date=2021-10-01"
        )

      assert %{"labels" => labels, "full_intervals" => full_intervals} = json_response(conn, 200)

      assert labels == ["2021-10-01", "2021-10-04", "2021-10-11", "2021-10-18", "2021-10-25"]

      assert full_intervals == %{
               "2021-10-01" => false,
               "2021-10-04" => true,
               "2021-10-11" => true,
               "2021-10-18" => true,
               "2021-10-25" => true
             }
    end

    test "shows perfect week-split range on week scale with full week indicators", %{
      conn: conn,
      site: site
    } do
      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=custom&metric=visitors&interval=week&from=2020-12-21&to=2021-02-07"
        )

      assert %{"labels" => labels, "full_intervals" => full_intervals} = json_response(conn, 200)

      assert labels == [
               "2020-12-21",
               "2020-12-28",
               "2021-01-04",
               "2021-01-11",
               "2021-01-18",
               "2021-01-25",
               "2021-02-01"
             ]

      assert full_intervals == %{
               "2020-12-21" => true,
               "2020-12-28" => true,
               "2021-01-04" => true,
               "2021-01-11" => true,
               "2021-01-18" => true,
               "2021-01-25" => true,
               "2021-02-01" => true
             }
    end

    test "shows imperfect month-split period on month scale with full month indicators", %{
      conn: conn,
      site: site
    } do
      conn =
        get(
          conn,
          "/api/stats/#{site.domain}/main-graph?period=custom&metric=visitors&interval=month&from=2021-09-06&to=2021-12-13"
        )

      assert %{"labels" => labels, "full_intervals" => full_intervals} = json_response(conn, 200)

      assert labels == ["2021-09-01", "2021-10-01", "2021-11-01", "2021-12-01"]

      assert full_intervals == %{
               "2021-09-01" => false,
               "2021-10-01" => true,
               "2021-11-01" => true,
               "2021-12-01" => false
             }
    end
  end
end
