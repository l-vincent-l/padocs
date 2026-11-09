defmodule YexBlockNote.Fixtures do
  @moduledoc """
  Documents as written by the BlockNote editor, in a `Yex.XmlFragment`.
  """

  @doc "An empty fragment, in a new document."
  def new_fragment, do: Yex.Doc.get_xml_fragment(Yex.Doc.new(), "blocknote")

  @doc """
  A fragment holding `blocks`, one per `{tag, text, nested blocks,
  attributes}`, the last two being optional; a text is a string, or a delta
  (a list of `%{insert, attributes}`).
  """
  def fragment_with(blocks) do
    fragment = new_fragment()
    Yex.XmlFragment.push(fragment, Yex.XmlElementPrelim.empty("blockGroup"))
    {:ok, group} = Yex.XmlFragment.fetch(fragment, 0)
    push_blocks(group, blocks)

    fragment
  end

  @doc """
  Pushes `blocks` (see `fragment_with/1`) to a blockGroup. Attributes are set
  once the elements exist: Yex ignores those of prelims.
  """
  def push_blocks(group, blocks) do
    for block <- blocks do
      {tag, text, children, attributes} =
        case block do
          {tag, text} -> {tag, text, [], %{}}
          {tag, text, children} -> {tag, text, children, %{}}
          block -> block
        end

      Yex.XmlElement.push(group, Yex.XmlElementPrelim.empty("blockContainer"))
      {:ok, container} = Yex.XmlElement.fetch(group, Yex.XmlElement.length(group) - 1)

      content =
        case text do
          "" -> []
          [_ | _] = delta -> [Yex.XmlTextPrelim.from(delta)]
          text -> [Yex.XmlTextPrelim.from(text)]
        end

      Yex.XmlElement.push(container, Yex.XmlElementPrelim.new(tag, content))
      {:ok, element} = Yex.XmlElement.fetch(container, 0)
      for {key, value} <- attributes, do: Yex.XmlElement.insert_attribute(element, key, value)

      if children != [] do
        Yex.XmlElement.push(container, Yex.XmlElementPrelim.empty("blockGroup"))
        {:ok, nested} = Yex.XmlElement.fetch(container, 1)
        push_blocks(nested, children)
      end
    end
  end
end
