defmodule Padocs.Document.Tag do
  @moduledoc """
  A label put on documents, shared by everyone: the same `label` is the same
  tag on all the documents carrying it, whoever put it there. A user only sees
  the tags of the documents they can read (see `Padocs.Document.visible_tags/1`).

  `key` is the label lowercased, unique: "Urgent" and "urgent" are one tag.
  `color` is picked from the label (see `color_for/1`), so that it tells
  nothing about the tag's other uses. A tag is deleted with its last document
  (see `Padocs.Document.remove_tag/3`).
  """
  use Ecto.Schema

  @colors [:lavender, :pink, :yellow, :mint, :sky, :peach]
  @max_length 40

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "tags" do
    field :label, :string
    field :key, :string
    field :color, Ecto.Enum, values: @colors
    many_to_many :documents, Padocs.Document.Document, join_through: Padocs.Document.TagDocument
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  `label` cleaned up for a tag: trimmed, inner spaces collapsed, at most 40
  characters. `nil` when nothing is left.
  """
  def normalize_label(label) when is_binary(label) do
    label
    |> String.split()
    |> Enum.join(" ")
    |> String.slice(0, @max_length)
    |> case do
      "" -> nil
      label -> label
    end
  end

  def normalize_label(_label), do: nil

  def key(label), do: String.downcase(label)

  @doc """
  Sorts `tags` by label as in a dictionary: case and accents ignored, so that
  "Épices" comes among the E (SQLite would put it after Z).
  """
  def sort_by_label(tags), do: Enum.sort_by(tags, &{sort_key(&1.label), &1.key})

  defp sort_key(label) do
    label
    |> key()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end

  @doc "The color of a new tag, the same for a given label."
  def color_for(label), do: Enum.at(@colors, :erlang.phash2(key(label), length(@colors)))
end
