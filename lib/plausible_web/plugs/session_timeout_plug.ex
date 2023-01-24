defmodule PlausibleWeb.SessionTimeoutPlug do
  import Plug.Conn

  def init(opts \\ []) do
    opts
  end

  def call(conn, opts) do
    timeout_at = get_session(conn, :session_timeout_at)
    user_id = get_session(conn, :current_user_id)

    cond do
      user_id && timeout_at && now() > timeout_at ->
        conn
        |> configure_session(drop: true)
        |> delete_resp_cookie("logged_in")

      user_id ->
        put_session(
          conn,
          :session_timeout_at,
          new_session_timeout_at(opts[:timeout_after_seconds])
        )

      true ->
        conn
    end
  end

  defp now do
    DateTime.utc_now() |> DateTime.to_unix()
  end

  defp new_session_timeout_at(timeout_after_seconds) do
    now() + timeout_after_seconds
  end
end
