defmodule PlausibleWeb.Api.StatsController.CountriesTest do
  use PlausibleWeb.ConnCase

  describe "GET /api/stats/:domain/countries" do
    setup [:create_user, :log_in, :create_new_site, :add_imported_data]

    test "returns top countries by new visitors", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview,
          country_code: "EE"
        ),
        build(:pageview,
          country_code: "EE"
        ),
        build(:pageview,
          country_code: "GB"
        ),
        build(:imported_locations,
          country: "EE"
        ),
        build(:imported_locations,
          country: "GB"
        )
      ])

      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day")

      assert json_response(conn, 200) == [
               %{
                 "code" => "EE",
                 "alpha_3" => "EST",
                 "name" => "Estonia",
                 "flag" => "🇪🇪",
                 "visitors" => 2,
                 "percentage" => 67
               },
               %{
                 "code" => "GB",
                 "alpha_3" => "GBR",
                 "name" => "United Kingdom",
                 "flag" => "🇬🇧",
                 "visitors" => 1,
                 "percentage" => 33
               }
             ]

      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day&with_imported=true")

      assert json_response(conn, 200) == [
               %{
                 "code" => "EE",
                 "alpha_3" => "EST",
                 "name" => "Estonia",
                 "flag" => "🇪🇪",
                 "visitors" => 3,
                 "percentage" => 60
               },
               %{
                 "code" => "GB",
                 "alpha_3" => "GBR",
                 "name" => "United Kingdom",
                 "flag" => "🇬🇧",
                 "visitors" => 2,
                 "percentage" => 40
               }
             ]
    end

    test "ignores unknown country code ZZ", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, country_code: "ZZ"),
        build(:imported_locations, country: "ZZ")
      ])

      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day&with_imported=true")

      assert json_response(conn, 200) == []
    end

    test "calculates conversion_rate when filtering for goal", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview,
          user_id: 1,
          country_code: "EE"
        ),
        build(:event, user_id: 1, name: "Signup"),
        build(:pageview,
          user_id: 2,
          country_code: "EE"
        ),
        build(:pageview,
          user_id: 3,
          country_code: "GB"
        ),
        build(:event, user_id: 3, name: "Signup")
      ])

      filters = Jason.encode!(%{"goal" => "Signup"})

      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day&filters=#{filters}")

      assert json_response(conn, 200) == [
               %{
                 "code" => "GB",
                 "alpha_3" => "GBR",
                 "name" => "United Kingdom",
                 "flag" => "🇬🇧",
                 "total_visitors" => 1,
                 "visitors" => 1,
                 "conversion_rate" => 100.0
               },
               %{
                 "code" => "EE",
                 "alpha_3" => "EST",
                 "name" => "Estonia",
                 "flag" => "🇪🇪",
                 "total_visitors" => 2,
                 "visitors" => 1,
                 "conversion_rate" => 50.0
               }
             ]
    end

    test "returns top countries with :is filter on custom pageview props", %{
      conn: conn,
      site: site
    } do
      populate_stats(site, [
        build(:pageview,
          user_id: 123,
          country_code: "EE"
        ),
        build(:pageview,
          user_id: 123,
          country_code: "EE",
          "meta.key": ["author"],
          "meta.value": ["John Doe"]
        ),
        build(:pageview,
          country_code: "GB",
          "meta.key": ["author"],
          "meta.value": ["other"]
        ),
        build(:pageview,
          country_code: "US"
        )
      ])

      filters = Jason.encode!(%{props: %{"author" => "John Doe"}})
      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day&filters=#{filters}")

      assert json_response(conn, 200) == [
               %{
                 "code" => "EE",
                 "alpha_3" => "EST",
                 "name" => "Estonia",
                 "flag" => "🇪🇪",
                 "visitors" => 1,
                 "percentage" => 100
               }
             ]
    end

    test "returns top countries with :is_not filter on custom pageview props", %{
      conn: conn,
      site: site
    } do
      populate_stats(site, [
        build(:pageview,
          user_id: 123,
          country_code: "EE",
          "meta.key": ["author"],
          "meta.value": ["John Doe"]
        ),
        build(:pageview,
          user_id: 123,
          country_code: "EE",
          "meta.key": ["author"],
          "meta.value": ["John Doe"]
        ),
        build(:pageview,
          country_code: "GB",
          "meta.key": ["author"],
          "meta.value": ["other"]
        ),
        build(:pageview,
          country_code: "GB"
        )
      ])

      filters = Jason.encode!(%{props: %{"author" => "!John Doe"}})
      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day&filters=#{filters}")

      assert json_response(conn, 200) == [
               %{
                 "code" => "GB",
                 "alpha_3" => "GBR",
                 "name" => "United Kingdom",
                 "flag" => "🇬🇧",
                 "visitors" => 2,
                 "percentage" => 100
               }
             ]
    end

    test "returns top countries with :is (none) filter on custom pageview props", %{
      conn: conn,
      site: site
    } do
      populate_stats(site, [
        build(:pageview,
          country_code: "EE",
          "meta.key": ["author"],
          "meta.value": ["John Doe"]
        ),
        build(:pageview,
          country_code: "GB",
          "meta.key": ["logged_in"],
          "meta.value": ["true"]
        ),
        build(:pageview,
          country_code: "GB"
        )
      ])

      filters = Jason.encode!(%{props: %{"author" => "(none)"}})
      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day&filters=#{filters}")

      assert json_response(conn, 200) == [
               %{
                 "code" => "GB",
                 "alpha_3" => "GBR",
                 "name" => "United Kingdom",
                 "flag" => "🇬🇧",
                 "visitors" => 2,
                 "percentage" => 100
               }
             ]
    end

    test "returns top countries with :is_not (none) filter on custom pageview props", %{
      conn: conn,
      site: site
    } do
      populate_stats(site, [
        build(:pageview,
          country_code: "EE",
          "meta.key": ["author"],
          "meta.value": ["John Doe"]
        ),
        build(:pageview,
          country_code: "EE",
          "meta.key": ["author"],
          "meta.value": [""]
        ),
        build(:pageview,
          country_code: "GB",
          "meta.key": ["logged_in"],
          "meta.value": ["true"]
        ),
        build(:pageview,
          country_code: "GB"
        )
      ])

      filters = Jason.encode!(%{props: %{"author" => "!(none)"}})
      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day&filters=#{filters}")

      assert json_response(conn, 200) == [
               %{
                 "code" => "EE",
                 "alpha_3" => "EST",
                 "name" => "Estonia",
                 "flag" => "🇪🇪",
                 "visitors" => 2,
                 "percentage" => 100
               }
             ]
    end

    test "when list is filtered by country returns one country only", %{conn: conn, site: site} do
      populate_stats(site, [
        build(:pageview, country_code: "EE"),
        build(:pageview, country_code: "EE"),
        build(:pageview, country_code: "GB")
      ])

      filters = Jason.encode!(%{country: "GB"})
      conn = get(conn, "/api/stats/#{site.domain}/countries?period=day&filters=#{filters}")

      assert json_response(conn, 200) == [
               %{
                 "code" => "GB",
                 "alpha_3" => "GBR",
                 "name" => "United Kingdom",
                 "flag" => "🇬🇧",
                 "visitors" => 1,
                 "percentage" => 100
               }
             ]
    end
  end
end
