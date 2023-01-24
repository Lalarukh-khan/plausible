defmodule Plausible.Site do
  @moduledoc """
  Site schema
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Plausible.Auth.User
  alias Plausible.Site.GoogleAuth

  @type t() :: %__MODULE__{}

  @derive {Jason.Encoder, only: [:domain, :timezone]}
  schema "sites" do
    field :domain, :string
    field :timezone, :string, default: "Etc/UTC"
    field :public, :boolean
    field :locked, :boolean
    field :stats_start_date, :date

    field :ingest_rate_limit_scale_seconds, :integer, default: 60
    field :ingest_rate_limit_threshold, :integer

    embeds_one :imported_data, Plausible.Site.ImportedData, on_replace: :update

    many_to_many :members, User, join_through: Plausible.Site.Membership
    has_many :memberships, Plausible.Site.Membership
    has_many :invitations, Plausible.Auth.Invitation
    has_one :google_auth, GoogleAuth
    has_one :weekly_report, Plausible.Site.WeeklyReport
    has_one :monthly_report, Plausible.Site.MonthlyReport
    has_one :custom_domain, Plausible.Site.CustomDomain
    has_one :spike_notification, Plausible.Site.SpikeNotification

    # If `from_cache?` is set, the struct might be incomplete - see `Plausible.Site.Cache`.
    # Use `Plausible.Repo.reload!(cached_site)` to pre-fill missing fields if
    # strictly necessary.
    field :from_cache?, :boolean, virtual: true, default: false

    timestamps()
  end

  def changeset(site, attrs \\ %{}) do
    site
    |> cast(attrs, [:domain, :timezone])
    |> validate_required([:domain, :timezone])
    |> clean_domain()
    |> validate_format(:domain, ~r/^[-\.\\\/:\p{L}\d]*$/u,
      message: "only letters, numbers, slashes and period allowed"
    )
    |> validate_domain_reserved_characters()
    |> unique_constraint(:domain,
      message:
        "This domain has already been taken. Perhaps one of your team members registered it? If that's not the case, please contact support@plausible.io"
    )
  end

  def crm_changeset(site, attrs) do
    site
    |> cast(attrs, [
      :timezone,
      :public,
      :stats_start_date,
      :ingest_rate_limit_threshold,
      :ingest_rate_limit_scale_seconds
    ])
    |> validate_required([:timezone, :public])
    |> validate_number(:ingest_rate_limit_scale_seconds,
      greater_than_or_equal_to: 1,
      message: "must be at least 1 second"
    )
    |> validate_number(:ingest_rate_limit_threshold,
      greater_than_or_equal_to: 0,
      message: "must be empty, zero or positive"
    )
  end

  def make_public(site) do
    change(site, public: true)
  end

  def make_private(site) do
    change(site, public: false)
  end

  def set_stats_start_date(site, val) do
    change(site, stats_start_date: val)
  end

  def start_import(site, start_date, end_date, imported_source, status \\ "importing") do
    change(site,
      imported_data: %{
        start_date: start_date,
        end_date: end_date,
        source: imported_source,
        status: status
      }
    )
  end

  def import_success(site) do
    change(site,
      stats_start_date: site.imported_data.start_date,
      imported_data: %{status: "ok"}
    )
  end

  def import_failure(site) do
    change(site, imported_data: %{status: "error"})
  end

  def set_imported_source(site, imported_source) do
    change(site,
      imported_data: %Plausible.Site.ImportedData{
        end_date: Timex.today(),
        source: imported_source
      }
    )
  end

  def remove_imported_data(site) do
    change(site, imported_data: nil)
  end

  @doc """
  Returns the date of the first recorded stat in the timezone configured by the user.
  This function does 2 transformations:
    UTC %NaiveDateTime{} -> Local %DateTime{} -> Local %Date

  ## Examples

    iex> Plausible.Site.local_start_date(%Plausible.Site{stats_start_date: nil})
    nil

    iex> utc_start = ~N[2022-09-28 00:00:00]
    iex> tz = "Europe/Helsinki"
    iex> site = %Plausible.Site{stats_start_date: utc_start, timezone: tz}
    iex> Plausible.Site.local_start_date(site)
    ~D[2022-09-28]

    iex> utc_start = ~N[2022-09-28 00:00:00]
    iex> tz = "America/Los_Angeles"
    iex> site = %Plausible.Site{stats_start_date: utc_start, timezone: tz}
    iex> Plausible.Site.local_start_date(site)
    ~D[2022-09-27]
  """
  def local_start_date(%__MODULE__{stats_start_date: nil}) do
    nil
  end

  def local_start_date(site) do
    site.stats_start_date
    |> Timex.Timezone.convert("UTC")
    |> Timex.Timezone.convert(site.timezone)
    |> Timex.to_date()
  end

  defp clean_domain(changeset) do
    clean_domain =
      (get_field(changeset, :domain) || "")
      |> String.trim()
      |> String.replace_leading("http://", "")
      |> String.replace_leading("https://", "")
      |> String.replace_leading("www.", "")
      |> String.replace_trailing("/", "")
      |> String.downcase()

    change(changeset, %{
      domain: clean_domain
    })
  end

  # https://tools.ietf.org/html/rfc3986#section-2.2
  @uri_reserved_chars ~w(: ? # [ ] @ ! $ & ' \( \) * + , ; =)
  defp validate_domain_reserved_characters(changeset) do
    domain = get_field(changeset, :domain) || ""

    if String.contains?(domain, @uri_reserved_chars) do
      add_error(
        changeset,
        :domain,
        "must not contain URI reserved characters #{@uri_reserved_chars}"
      )
    else
      changeset
    end
  end
end
