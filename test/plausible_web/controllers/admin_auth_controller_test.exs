defmodule PlausibleWeb.AdminAuthControllerTest do
  use PlausibleWeb.ConnCase
  alias Plausible.Release

  setup_patch_env(:is_selfhost, true)

  describe "GET /" do
    test "disable registration", %{conn: conn} do
      prevent_first_launch()
      patch_config(disable_registration: true)
      conn = get(conn, "/register")
      assert redirected_to(conn) == "/login"
    end

    test "disable registration + first launch", %{conn: conn} do
      patch_config(disable_registration: true)
      assert Release.should_be_first_launch?()

      # "first launch" takes precedence
      conn = get(conn, "/register")
      assert html_response(conn, 200) =~ "Enter your details"
    end
  end

  def patch_config(config) do
    updated_config = Keyword.merge([disable_registration: false], config)
    patch_env(:selfhost, updated_config)
  end

  defp prevent_first_launch do
    insert(:user)
  end
end
