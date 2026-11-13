defmodule Padocs.Document.PolicyTest do
  use ExUnit.Case, async: true

  alias Padocs.Document.Policy

  test "what each role may do" do
    for {role, allowed} <- [
          owner: [:read, :write, :share],
          editor: [:read, :write],
          viewer: [:read],
          nil: []
        ],
        action <- [:read, :write, :share] do
      assert Policy.can?(role, action) == action in allowed, "#{role} #{action}"
    end
  end
end
