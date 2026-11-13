defmodule Padocs.Document.TagSearch do
  @moduledoc """
  How many times a user searched the documents of a tag (`count`), and when
  they last did: their most searched tags come first in the search modal (see
  `Padocs.Document.top_tags/2`). Deleted with its user or its tag
  (`ON DELETE CASCADE`).
  """
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "tag_searches" do
    belongs_to :user, Padocs.Accounts.User, primary_key: true
    belongs_to :tag, Padocs.Document.Tag, primary_key: true
    field :count, :integer, default: 1
    field :searched_at, :utc_datetime_usec
  end
end
