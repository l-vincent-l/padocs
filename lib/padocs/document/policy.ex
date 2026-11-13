defmodule Padocs.Document.Policy do
  @moduledoc """
  What each role may do on a document: the owner anything, an editor read and
  write, a viewer only read. `nil` is the role of a user without access.
  """

  @type role :: :owner | :editor | :viewer | nil
  @type action :: :read | :write | :share

  @spec can?(role(), action()) :: boolean()
  def can?(:owner, _action), do: true
  def can?(:editor, action), do: action in [:read, :write]
  def can?(:viewer, action), do: action == :read
  def can?(nil, _action), do: false
end
