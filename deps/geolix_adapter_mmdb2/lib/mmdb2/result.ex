defmodule Geolix.Adapter.MMDB2.Result do
  @moduledoc false

  alias Geolix.Adapter.MMDB2.Result

  @mapping [
    {"GeoIP2-City", Result.City},
    {"GeoIP2-Country", Result.Country},
    {"GeoIP2-Enterprise", Result.Enterprise},
    {"GeoLite2-City", Result.City},
    {"GeoLite2-Country", Result.Country}
  ]

  @mapping_flat [
    {"GeoIP2-Anonymous-IP", Result.AnonymousIP},
    {"GeoIP2-Connection-Type", Result.ConnectionType},
    {"GeoIP2-Domain", Result.Domain},
    {"GeoIP2-ISP", Result.ISP},
    {"GeoLite2-ASN", Result.ASN}
  ]

  @doc """
  Convert raw result map into struct.
  """
  @spec to_struct(type :: String.t(), data :: map, locale :: atom) :: map
  for {type, model} <- @mapping do
    def to_struct(unquote(type), data, locale) do
      structify(unquote(model), data, locale)
    end
  end

  for {type, model} <- @mapping_flat do
    def to_struct(unquote(type), data, locale) do
      structify_flat(unquote(model), data, locale)
    end
  end

  def to_struct(_type, data, _), do: data

  defp structify(model, data, locale) do
    result = model.from(data, locale)
    traits = Map.put(result.traits, :ip_address, data[:ip_address])

    Map.put(result, :traits, traits)
  end

  defp structify_flat(model, data, locale), do: model.from(data, locale)
end
