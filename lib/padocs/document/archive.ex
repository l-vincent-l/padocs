defmodule Padocs.Document.Archive do
  @moduledoc """
  The plan of an archive's import: from the paths of a zip's entries, read
  in the browser, the documents to create, which the browser then converts
  and sends one by one, parents first (see the DocumentImport hook).

  The archive becomes a tree under one root document: the folder alone at
  the top of the archive, or else a document named after the archive. Each
  folder holding documents becomes a parent document, each Markdown, HTML,
  text or Word file a document. A file and a folder of the same name, side
  by side, make one document, the file's content over the folder's
  documents: Notion exports pages so, as `Page.md` beside `Page/`. Siblings
  come by title, whatever the case.

  The images are attachments, uploaded when a document links to them. Hidden
  and system files (`.obsidian/`, `.DS_Store`, `__MACOSX/`...) are left out
  silently; unsafe paths (`..`, absolute) and other files are reported.
  """

  @formats %{
    ".md" => "markdown",
    ".markdown" => "markdown",
    ".txt" => "markdown",
    ".html" => "html",
    ".htm" => "html",
    ".docx" => "docx"
  }

  @images ~w(.png .jpg .jpeg .gif .webp)

  @system_files ~w(thumbs.db desktop.ini)

  @max_documents 1000

  # The id Notion puts at the end of the names it exports
  @notion_id ~r/\s+[0-9a-f]{32}$/

  @doc """
  The plan of the import of the archive of `name` holding the files of
  `paths`:

    * `documents` - the documents to create, parents first, each
      `%{key, parent, title, path, format}`: `parent` the key of its parent
      (`nil` for the root), `path` and `format` (`"markdown"`, `"html"` or
      `"docx"`) those of its file, `nil` for a folder
    * `attachments` - the paths of the images
    * `skipped` - the files not imported, each `%{path, reason}`, the reason
      being `:unsafe`, `:unsupported` or `:too_many`

  At most `max_documents` documents (#{@max_documents} by default), the root
  included; the files of the others are reported as `:too_many`.
  """
  def plan(paths, name, opts \\ []) do
    max = Keyword.get(opts, :max_documents, @max_documents)

    {files, attachments, skipped} =
      paths
      |> Enum.reject(&String.ends_with?(&1, ["/", "\\"]))
      |> Enum.reduce({[], [], []}, fn path, {files, attachments, skipped} ->
        case classify(path) do
          {:document, segments, format} ->
            {[{segments, path, format} | files], attachments, skipped}

          :attachment ->
            {files, [path | attachments], skipped}

          :ignored ->
            {files, attachments, skipped}

          {:skipped, reason} ->
            {files, attachments, [%{path: path, reason: reason} | skipped]}
        end
      end)

    {documents, too_many} =
      files
      |> build_tree()
      |> root(name)
      |> flatten()
      |> Enum.split(max)

    %{
      documents: documents,
      attachments: Enum.reverse(attachments),
      skipped:
        Enum.reverse(skipped) ++
          for(%{path: path} <- too_many, path, do: %{path: path, reason: :too_many})
    }
  end

  defp classify(path) do
    segments = String.split(path, ["/", "\\"])
    basename = List.last(segments)
    extension = basename |> Path.extname() |> String.downcase()

    cond do
      String.starts_with?(path, ["/", "\\"]) or Enum.any?(segments, &(&1 in ["", ".", ".."])) ->
        {:skipped, :unsafe}

      Enum.any?(segments, &(String.starts_with?(&1, ".") or &1 == "__MACOSX")) or
          String.downcase(basename) in @system_files ->
        :ignored

      format = @formats[extension] ->
        {:document, segments, format}

      extension in @images ->
        :attachment

      true ->
        {:skipped, :unsupported}
    end
  end

  # A tree of nodes, %{name => %{file: {path, format} | nil, children: tree}}:
  # a file of stem "Page" and a folder "Page" are one node.
  defp build_tree(files) do
    Enum.reduce(files, %{}, fn {segments, path, format}, tree ->
      {folders, [basename]} = Enum.split(segments, -1)
      put_file(tree, folders, Path.rootname(basename), {path, format})
    end)
  end

  defp put_file(tree, [], stem, file) do
    case Map.get(tree, stem) do
      nil ->
        Map.put(tree, stem, %{file: file, children: %{}})

      %{file: nil} = folder ->
        Map.put(tree, stem, %{folder | file: file})

      # two files of the same stem (a.md and a.html): this one by its full name
      _taken ->
        {path, _format} = file
        Map.put(tree, Path.basename(path), %{file: file, children: %{}})
    end
  end

  defp put_file(tree, [folder | rest], stem, file) do
    node = Map.get(tree, folder, %{file: nil, children: %{}})
    Map.put(tree, folder, %{node | children: put_file(node.children, rest, stem, file)})
  end

  # The root: the folder alone at the top, without a file beside it, or a
  # node named after the archive.
  defp root(tree, _name) when tree == %{}, do: nil

  defp root(tree, name) do
    case Map.to_list(tree) do
      [{folder, %{file: nil} = node}] -> {folder, node}
      _ -> {name |> Path.basename() |> Path.rootname(), %{file: nil, children: tree}}
    end
  end

  # The documents, each node before its children, siblings by title.
  defp flatten(nil), do: []

  defp flatten(root) do
    {documents, _next} = flatten_node(root, nil, 0)
    documents
  end

  defp flatten_node({name, node}, parent, key) do
    {path, format} = node.file || {nil, nil}
    document = %{key: key, parent: parent, title: title(name), path: path, format: format}

    {children, next} =
      node.children
      |> Enum.sort_by(fn {name, _node} -> {String.downcase(title(name)), name} end)
      |> Enum.flat_map_reduce(key + 1, fn child, next -> flatten_node(child, key, next) end)

    {[document | children], next}
  end

  defp title(name), do: name |> String.replace(@notion_id, "") |> String.trim()

  @doc """
  The title and the tags given by the YAML front matter of a file (the text
  between its `---` lines), as Obsidian, Hugo or Jekyll write it, or by the
  properties opening a Logseq page (`title:: …`, `tags:: …`, on its first
  lines): `%{title: title | nil, tags: [tag]}`. The tags (`tags` or `tag`)
  are an inline list (`[a, "b c"]`), a dashed one, or separated by commas;
  a `#` before one, or the `[[…]]` around it, is dropped. Not a YAML parser:
  only those keys are read, on lines of their own.
  """
  def front_matter(nil), do: %{title: nil, tags: []}

  def front_matter(yaml) do
    # Logseq's `key:: value`, maybe in the page's first block (`- key::`),
    # read as YAML's `key: value`
    lines =
      yaml
      |> String.split(~r/\R/)
      |> Enum.map(&Regex.replace(~r/^\s*(?:-\s+)?([\w-]+)::(?=\s|$)/, &1, "\\1:"))

    %{
      title: lines |> value("title") |> scalar(),
      tags: tags(lines)
    }
  end

  # The text after `key:`, on its line.
  defp value(lines, key) do
    Enum.find_value(lines, fn line ->
      case Regex.run(~r/^#{key}\s*:\s*(.*)$/, line) do
        [_, value] -> String.trim(value)
        nil -> nil
      end
    end)
  end

  defp tags(lines) do
    case Enum.find_index(lines, &Regex.match?(~r/^tags?\s*:/, &1)) do
      nil ->
        []

      index ->
        value = lines |> Enum.at(index) |> String.replace(~r/^tags?\s*:/, "") |> String.trim()

        items =
          cond do
            value == "" ->
              lines
              |> Enum.drop(index + 1)
              |> Enum.take_while(&Regex.match?(~r/^\s+-\s*/, &1))
              |> Enum.map(&String.replace(&1, ~r/^\s+-\s*/, ""))

            # Logseq's links to pages, `[[a b]], [[c]]` or `[[a b]] [[c]]`
            String.starts_with?(value, "[[") ->
              Regex.scan(~r/\[\[([^\]]+)\]\]|([^,\[\]\s][^,\[\]]*)/, value)
              |> Enum.map(fn match -> match |> Enum.drop(1) |> Enum.join() end)

            String.starts_with?(value, "[") ->
              value |> String.trim_leading("[") |> String.trim_trailing("]") |> String.split(",")

            true ->
              String.split(value, ",")
          end

        items
        |> Enum.map(&scalar/1)
        |> Enum.map(&(&1 && &1 |> String.trim_leading("#") |> unlink()))
        |> Enum.reject(&(&1 in [nil, ""]))
    end
  end

  # `[[a]]`, Logseq's link to a page, as `a`.
  defp unlink(tag) do
    case Regex.run(~r/^\[\[(.*)\]\]$/, tag) do
      [_, inner] -> String.trim(inner)
      nil -> tag
    end
  end

  # A YAML scalar: unquoted, `nil` when empty.
  defp scalar(nil), do: nil

  defp scalar(value) do
    value = String.trim(value)

    value =
      case Regex.run(~r/^(["'])(.*)\1$/, value) do
        [_, _quote, inner] -> inner
        nil -> value
      end

    if String.trim(value) == "", do: nil, else: String.trim(value)
  end
end
