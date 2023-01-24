defmodule Plausible.Workers.SendSiteSetupEmails do
  use Plausible.Repo
  use Oban.Worker, queue: :site_setup_emails
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    send_create_site_emails()
    send_setup_help_emails()
    send_setup_success_emails()

    :ok
  end

  defp send_create_site_emails() do
    q =
      from(s in Plausible.Auth.User,
        left_join: se in "create_site_emails",
        on: se.user_id == s.id,
        where: is_nil(se.id),
        where:
          s.inserted_at > fragment("(now() at time zone 'utc') - '72 hours'::interval") and
            s.inserted_at < fragment("(now() at time zone 'utc') - '48 hours'::interval"),
        preload: :sites
      )

    for user <- Repo.all(q) do
      if Enum.empty?(user.sites) do
        send_create_site_email(user)
      end
    end
  end

  defp send_setup_help_emails() do
    q =
      from(s in Plausible.Site,
        left_join: se in "setup_help_emails",
        on: se.site_id == s.id,
        where: is_nil(se.id),
        where: s.inserted_at > fragment("(now() at time zone 'utc') - '72 hours'::interval")
      )

    for site <- Repo.all(q) do
      owner =
        Plausible.Sites.owner_for(site)
        |> Repo.preload(:subscription)

      setup_completed = Plausible.Sites.has_stats?(site)
      hours_passed = Timex.diff(Timex.now(), site.inserted_at, :hours)

      if !setup_completed && hours_passed > 47 do
        send_setup_help_email(owner, site)
      end
    end
  end

  defp send_setup_success_emails() do
    q =
      from(s in Plausible.Site,
        left_join: se in "setup_success_emails",
        on: se.site_id == s.id,
        where: is_nil(se.id),
        where: s.inserted_at > fragment("(now() at time zone 'utc') - '72 hours'::interval")
      )

    for site <- Repo.all(q) do
      owner =
        Plausible.Sites.owner_for(site)
        |> Repo.preload(:subscription)

      if Plausible.Sites.has_stats?(site) do
        send_setup_success_email(owner, site)
      end
    end
  end

  defp send_create_site_email(user) do
    PlausibleWeb.Email.create_site_email(user)
    |> Plausible.Mailer.send()

    Repo.insert_all("create_site_emails", [
      %{
        user_id: user.id,
        timestamp: NaiveDateTime.utc_now()
      }
    ])
  end

  defp send_setup_success_email(user, site) do
    PlausibleWeb.Email.site_setup_success(user, site)
    |> Plausible.Mailer.send()

    Repo.insert_all("setup_success_emails", [
      %{
        site_id: site.id,
        timestamp: NaiveDateTime.utc_now()
      }
    ])
  end

  defp send_setup_help_email(user, site) do
    PlausibleWeb.Email.site_setup_help(user, site)
    |> Plausible.Mailer.send()

    Repo.insert_all("setup_help_emails", [
      %{
        site_id: site.id,
        timestamp: NaiveDateTime.utc_now()
      }
    ])
  end
end
