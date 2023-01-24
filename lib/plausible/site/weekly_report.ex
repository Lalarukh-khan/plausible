defmodule Plausible.Site.WeeklyReport do
  use Ecto.Schema
  import Ecto.Changeset

  schema "weekly_reports" do
    field :recipients, {:array, :string}
    belongs_to :site, Plausible.Site

    timestamps()
  end

  def changeset(settings, attrs \\ %{}) do
    settings
    |> cast(attrs, [:site_id, :recipients])
    |> validate_required([:site_id, :recipients])
    |> unique_constraint(:site)
  end

  def add_recipient(report, recipient) do
    report
    |> change(recipients: report.recipients ++ [recipient])
  end

  def remove_recipient(report, recipient) do
    report
    |> change(recipients: List.delete(report.recipients, recipient))
  end
end
