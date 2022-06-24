defmodule Schema.Enums do
  @moduledoc """
    Helper function to deal with schema enum attributes and values.
  """

  @doc """
    Returns the enum sibling name.
  """
  @spec sibling(atom(), map()) :: atom()
  def sibling(key, field) do
    case field[:sibling] do
      nil ->
        Atom.to_string(key) |> base_name()

      name ->
        name
    end
    |> String.to_atom()
  end

  @doc """
    Returns the base attribute name by trimming the _id or _ids.
  """
  @spec base_name(String.t()) :: String.t()
  def base_name(name) do
    cond do
      String.ends_with?(name, "_id") ->
        String.trim(name, "_id")

      String.ends_with?(name, "_id") ->
        String.trim(name, "_ids") <> "s"

      true ->
        name
    end
  end
end
