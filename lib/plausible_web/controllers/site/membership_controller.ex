defmodule PlausibleWeb.Site.MembershipController do
  @moduledoc """
    This controller deals with user management via the UI in Site Settings -> People. It's important to enforce permissions in this controller.

    Owner - Can manage users, can trigger a 'transfer ownership' request
    Admin - Can manage users
    Viewer - Can not access user management settings
    Anyone - Can accept invitations

    Everything else should be explicitly disallowed.
  """

  use PlausibleWeb, :controller
  use Plausible.Repo
  alias Plausible.Sites
  alias Plausible.Site.Membership
  alias Plausible.Auth.Invitation

  @only_owner_is_allowed_to [:transfer_ownership_form, :transfer_ownership]

  plug PlausibleWeb.RequireAccountPlug
  plug PlausibleWeb.AuthorizeSiteAccess, [:owner] when action in @only_owner_is_allowed_to

  plug PlausibleWeb.AuthorizeSiteAccess,
       [:owner, :admin] when action not in @only_owner_is_allowed_to

  def invite_member_form(conn, _params) do
    site = Sites.get_for_user!(conn.assigns[:current_user].id, conn.assigns[:site].domain)

    render(
      conn,
      "invite_member_form.html",
      site: site,
      layout: {PlausibleWeb.LayoutView, "focus.html"},
      skip_plausible_tracking: true
    )
  end

  def invite_member(conn, %{"email" => email, "role" => role}) do
    site_domain = conn.assigns[:site].domain
    site = Sites.get_for_user!(conn.assigns[:current_user].id, site_domain)
    user = Plausible.Auth.find_user_by(email: email)

    if user && Sites.is_member?(user.id, site) do
      msg = "Cannot send invite because #{user.email} is already a member of #{site.domain}"

      render(conn, "invite_member_form.html",
        error: msg,
        site: site,
        layout: {PlausibleWeb.LayoutView, "focus.html"},
        skip_plausible_tracking: true
      )
    else
      case Repo.insert(
             Invitation.new(%{
               email: email,
               role: role,
               site_id: site.id,
               inviter_id: conn.assigns[:current_user].id
             })
           ) do
        {:ok, invitation} ->
          invitation = Repo.preload(invitation, [:site, :inviter])

          email_template =
            if user do
              PlausibleWeb.Email.existing_user_invitation(invitation)
            else
              PlausibleWeb.Email.new_user_invitation(invitation)
            end

          Plausible.Mailer.send(email_template)

          conn
          |> put_flash(
            :success,
            "#{email} has been invited to #{site_domain} as #{PlausibleWeb.SiteView.with_indefinite_article(role)}"
          )
          |> redirect(to: Routes.site_path(conn, :settings_people, site.domain))

        {:error, changeset} ->
          error_msg =
            case changeset.errors[:invitation] do
              {"already sent", _} ->
                "This invitation has been already sent. To send again, remove it from pending invitations first."

              _ ->
                "Something went wrong."
            end

          conn
          |> put_flash(
            :error,
            error_msg
          )
          |> redirect(to: Routes.site_path(conn, :settings_people, site.domain))
      end
    end
  end

  def transfer_ownership_form(conn, _params) do
    site_domain = conn.assigns[:site].domain
    site = Sites.get_for_user!(conn.assigns[:current_user].id, site_domain)

    render(
      conn,
      "transfer_ownership_form.html",
      site: site,
      layout: {PlausibleWeb.LayoutView, "focus.html"},
      skip_plausible_tracking: true
    )
  end

  def transfer_ownership(conn, %{"email" => email}) do
    site_domain = conn.assigns[:site].domain
    site = Sites.get_for_user!(conn.assigns[:current_user].id, site_domain)
    user = Plausible.Auth.find_user_by(email: email)

    invitation =
      Invitation.new(%{
        email: email,
        role: :owner,
        site_id: site.id,
        inviter_id: conn.assigns[:current_user].id
      })
      |> Repo.insert!()
      |> Repo.preload([:site, :inviter])

    PlausibleWeb.Email.ownership_transfer_request(invitation, user)
    |> Plausible.Mailer.send()

    conn
    |> put_flash(:success, "Site transfer request has been sent to #{email}")
    |> redirect(to: Routes.site_path(conn, :settings_people, site.domain))
  end

  @doc """
    Updates the role of a user. The user being updated could be the same or different from the user taking
    the action. When updating the role, it's important to enforce permissions:

    Owner - Can update anyone's role except for themselves. If they want to change their own role, they have to use the 'transfer ownership' feature.
    Admin - Can update anyone's role except for owners. Can downgrade their own access to 'viewer'. Can promote a viewer to admin.
  """
  @role_mappings Membership
                 |> Ecto.Enum.mappings(:role)
                 |> Enum.map(fn {k, v} -> {v, k} end)
                 |> Enum.into(%{})

  def update_role(conn, %{"id" => id, "new_role" => new_role_str}) do
    %{site: site, current_user: current_user, current_user_role: current_user_role} = conn.assigns

    membership = Repo.get!(Membership, id) |> Repo.preload(:user)
    new_role = Map.fetch!(@role_mappings, new_role_str)

    can_grant_role? =
      if membership.user.id == current_user.id do
        can_grant_role_to_self?(current_user_role, new_role)
      else
        can_grant_role_to_other?(current_user_role, new_role)
      end

    if can_grant_role? do
      membership =
        membership
        |> Membership.changeset(%{role: new_role})
        |> Repo.update!()

      redirect_target =
        if membership.user.id == current_user.id and new_role == :viewer do
          "/#{URI.encode_www_form(site.domain)}"
        else
          Routes.site_path(conn, :settings_people, site.domain)
        end

      conn
      |> put_flash(
        :success,
        "#{membership.user.name} is now #{PlausibleWeb.SiteView.with_indefinite_article(new_role_str)}"
      )
      |> redirect(to: redirect_target)
    else
      conn
      |> put_flash(:error, "You are not allowed to grant the #{new_role} role")
      |> redirect(to: Routes.site_path(conn, :settings_people, site.domain))
    end
  end

  defp can_grant_role_to_self?(:admin, :viewer), do: true
  defp can_grant_role_to_self?(_, _), do: false

  defp can_grant_role_to_other?(:owner, :admin), do: true
  defp can_grant_role_to_other?(:owner, :viewer), do: true
  defp can_grant_role_to_other?(:admin, :admin), do: true
  defp can_grant_role_to_other?(:admin, :viewer), do: true
  defp can_grant_role_to_other?(_, _), do: false

  def remove_member(conn, %{"id" => id}) do
    site = conn.assigns[:site]
    site_id = site.id

    membership_q =
      from m in Membership,
        where: m.id == ^id,
        where: m.site_id == ^site_id,
        inner_join: user in assoc(m, :user),
        inner_join: site in assoc(m, :site),
        preload: [user: user, site: site]

    membership = Repo.one(membership_q)

    if membership do
      Repo.delete!(membership)

      membership
      |> PlausibleWeb.Email.site_member_removed()
      |> Plausible.Mailer.send()

      redirect_target =
        if membership.user.id == conn.assigns[:current_user].id do
          "/#{URI.encode_www_form(membership.site.domain)}"
        else
          Routes.site_path(conn, :settings_people, site.domain)
        end

      conn
      |> put_flash(
        :success,
        "#{membership.user.name} has been removed from #{site.domain}"
      )
      |> redirect(to: redirect_target)
    else
      conn
      |> put_flash(
        :error,
        "Failed to find membership to remove"
      )
      |> redirect(to: Routes.site_path(conn, :settings_people, site.domain))
    end
  end
end
