defimpl Bamboo.Formatter, for: Plausible.Auth.User do
  def format_email_address(user, _opts) do
    {user.name, user.email}
  end
end

defimpl FunWithFlags.Actor, for: Plausible.Auth.User do
  def id(%{id: id}) do
    "user:#{id}"
  end
end

defmodule Plausible.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset

  @type t() :: %__MODULE__{}

  @required [:email, :name, :password, :password_confirmation]
  schema "users" do
    field :email, :string
    field :password_hash
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :name, :string
    field :last_seen, :naive_datetime
    field :trial_expiry_date, :date
    field :theme, :string
    field :email_verified, :boolean
    embeds_one :grace_period, Plausible.Auth.GracePeriod, on_replace: :update

    has_many :site_memberships, Plausible.Site.Membership
    has_many :sites, through: [:site_memberships, :site]
    has_many :api_keys, Plausible.Auth.ApiKey
    has_one :google_auth, Plausible.Site.GoogleAuth
    has_one :subscription, Plausible.Billing.Subscription
    has_one :enterprise_plan, Plausible.Billing.EnterprisePlan

    timestamps()
  end

  def new(attrs \\ %{}) do
    %Plausible.Auth.User{}
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> validate_length(:password, min: 6, message: "has to be at least 6 characters")
    |> validate_length(:password, max: 64, message: "cannot be longer than 64 characters")
    |> validate_confirmation(:password)
    |> hash_password()
    |> start_trial
    |> set_email_verified
    |> unique_constraint(:email)
  end

  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:email, :name, :email_verified, :theme, :trial_expiry_date])
    |> validate_required([:email, :name, :email_verified])
    |> unique_constraint(:email)
  end

  def set_password(user, password) do
    hash = Plausible.Auth.Password.hash(password)

    user
    |> cast(%{password: password}, [:password])
    |> validate_required(:password)
    |> validate_length(:password, min: 6, message: "has to be at least 6 characters")
    |> cast(%{password_hash: hash}, [:password_hash])
  end

  def hash_password(%{errors: [], changes: changes} = changeset) do
    hash = Plausible.Auth.Password.hash(changes[:password])
    change(changeset, password_hash: hash)
  end

  def hash_password(changeset), do: changeset

  def remove_trial_expiry(user) do
    change(user, trial_expiry_date: nil)
  end

  def start_trial(user) do
    change(user, trial_expiry_date: trial_expiry())
  end

  def end_trial(user) do
    change(user, trial_expiry_date: Timex.today() |> Timex.shift(days: -1))
  end

  defp trial_expiry() do
    if Application.get_env(:plausible, :is_selfhost) do
      Timex.today() |> Timex.shift(years: 100)
    else
      Timex.today() |> Timex.shift(days: 30)
    end
  end

  defp set_email_verified(user) do
    if Keyword.fetch!(Application.get_env(:plausible, :selfhost), :enable_email_verification) do
      change(user, email_verified: false)
    else
      change(user, email_verified: true)
    end
  end
end
