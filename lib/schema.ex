defmodule Schema do
  @moduledoc """
  Schema keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Schema.Repo
  alias Schema.Cache

  @doc """
    Returns the schema version string.
  """
  @spec version :: String.t()
  def version(), do: Repo.version()

  @doc """
    Returns the event categories.
  """
  @spec categories :: map()
  def categories(), do: Repo.categories()

  @spec categories(atom | String.t()) :: nil | Cache.category_t()
  def categories(id) when is_atom(id), do: Repo.categories(id)
  def categories(id) when is_binary(id), do: Repo.categories(String.to_atom(id))

  @doc """
    Returns the event dictionary.
  """
  @spec dictionary :: Cache.dictionary_t()
  def dictionary(), do: Repo.dictionary()

  @doc """
    Returns all event classes.
  """
  def classes(), do: Repo.classes()
  @spec classes() :: list()

  @doc """
    Returns a single event class.
  """
  @spec classes(atom | String.t()) :: nil | Cache.class_t()
  def classes(id) when is_atom(id), do: Repo.classes(id)
  def classes(id) when is_binary(id), do: Repo.classes(String.to_atom(id))

  @doc """
  Finds a class by the class uid value.
  """
  @spec find_class(integer()) :: nil | Cache.class_t()
  def find_class(uid) when is_integer(uid), do: Repo.find_class(uid)

  @doc """
    Returns all objects.
  """
  @spec objects() :: map()
  def objects(), do: Repo.objects()

  @doc """
    Returns a single objects.
  """
  @spec objects(atom | String.t()) :: nil | Cache.object_t()
  def objects(id) when is_atom(id), do: Repo.objects(id)
  def objects(id) when is_binary(id), do: Repo.objects(String.to_atom(id))

  @spec to_uid(binary) :: atom
  def to_uid(name), do: Cache.to_uid(name)

  def event(class) when is_atom(class) do
    Schema.classes(class) |> Schema.Generator.event()
  end

  def event(class) when is_map(class) do
    Schema.Generator.event(class)
  end

  @spec generate(%{:type => any, optional(any) => any}) :: any
  def generate(type) when is_map(type) do
    Schema.Generator.generate(type)
  end
end
