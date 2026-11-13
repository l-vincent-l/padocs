defmodule Padocs.Document.Search do
  @moduledoc """
  Full-text search in the documents' titles and bodies.

  One index, in memory, holds all the documents, those in the trash
  included: `Padocs.Document.SearchIndex` builds it when the application
  starts and updates the documents that changed (`index_documents/2`). A
  search (`search/3`) runs in the caller's process, among the documents the
  user can read: their ids, read from the database, filter the query, so
  that the index needs no change when an access does. The index stores the
  text of the bodies, to cut the snippets of the results from them.

  Titles and bodies are analyzed as French: words are reduced to their stem
  ("statut" finds "statuts") and accents are ignored ("ecole" finds "école").
  The snippets mark the words found that way.

  The last word of a query, which may be being typed, also finds the words it
  starts ("associa" finds "association").

  The ids of the documents' tags are indexed too, so that a search can be
  limited to the documents carrying a tag before keeping the best matches.
  """
  alias Padocs.Document
  alias Padocs.Document.{SearchIndex, Snippet}
  alias TantivyEx.{Index, IndexWriter, Query, Schema, Searcher, Tokenizer}

  # The minimum tantivy accepts for one indexing thread; the default is 50 MB.
  @writer_memory_budget 15_000_000
  @limit 20
  @snippet_length 200
  @tokenizer "padocs_fr"
  # Shorter, a word being typed would find too many words
  @prefix_min_length 2
  # The documents read from the database at a time when indexing them all
  @chunk_size 100

  @doc """
  The documents `user` can read matching `query`, best match first, with in
  their `snippet` the fragment of their body around the words of the query
  (see `Padocs.Document.Snippet.segments/2`), `nil` when only the title
  matches. An invalid query (e.g. `cats AND (`) matches nothing, as all do
  before the index is started. With `tag_id`, only among the documents
  carrying that tag (when they were last indexed).
  """
  def search(query, user, tag_id \\ nil) do
    with query when query != "" <- String.trim(query),
         index when index != nil <- SearchIndex.index(),
         [_ | _] = ids <- Document.list_readable_ids(user),
         {:ok, hits, snippet} <- search_hits(index, query, ids, tag_id) do
      bodies = Map.new(hits)

      hits
      |> Enum.map(fn {id, _body} -> id end)
      |> load_documents(user)
      |> Enum.map(&%{&1 | snippet: snippet.(bodies[&1.id])})
    else
      _ -> []
    end
  end

  ## Indexing, by SearchIndex

  @doc "A new, empty index, and its writer: `{:ok, index, writer}`."
  def new_index do
    with :ok <- register_tokenizer(),
         {:ok, index} <- Index.create_in_ram(schema()),
         {:ok, writer} <- IndexWriter.new(index, @writer_memory_budget) do
      {:ok, index, writer}
    end
  end

  @doc "Indexes all the documents, in a new index (see `new_index/0`)."
  def index_all(writer) do
    Document.list_document_ids()
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce_while(:ok, fn ids, :ok ->
      case add_documents(writer, Document.list_documents_with_text(ids)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
    |> commit(writer)
  end

  @doc """
  Indexes the documents of `ids` again, as they are now in the database:
  those deleted for good are only removed from the index.
  """
  def index_documents(writer, ids) do
    schema = schema()

    ids
    |> Enum.reduce_while(:ok, fn id, :ok ->
      with {:ok, term} <- Query.term(schema, "id", id),
           :ok <- IndexWriter.delete_documents(writer, term) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      :ok -> add_documents(writer, Document.list_documents_with_text(ids))
      error -> error
    end
    |> commit(writer)
  end

  defp commit(:ok, writer), do: IndexWriter.commit(writer)
  defp commit(error, _writer), do: error

  # Registered globally, then given to the indexes created afterwards; again
  # for each index, which only replaces it.
  # Lowercased, stemmed as French, accents folded, words over 40 bytes dropped.
  defp register_tokenizer do
    Tokenizer.register_text_analyzer(@tokenizer, "simple", true, nil, "fr", 40, true)
  end

  defp schema do
    Schema.new()
    # Whole: one term, to filter and delete by
    |> Schema.add_text_field_with_tokenizer("id", :text_stored, "raw")
    |> Schema.add_text_field_with_tokenizer("title", :text, @tokenizer)
    |> Schema.add_text_field_with_tokenizer("body", :text_stored, @tokenizer)
    # The ids of the tags, separated by spaces: one term each
    |> Schema.add_text_field_with_tokenizer("tags", :text, "whitespace")
  end

  defp add_documents(writer, documents) do
    Enum.reduce_while(documents, :ok, fn {document, text, tag_ids}, :ok ->
      fields = %{
        "id" => document.id,
        "title" => document.title || "",
        "body" => text,
        "tags" => Enum.join(tag_ids, " ")
      }

      case IndexWriter.add_document(writer, fields) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  ## Searching

  # `Searcher.search/3` with a string matches every document, and
  # `Searcher.search_with_parser/6` passes the schema where the index is
  # expected: the query is parsed here.
  # The `{id, body}` of the matching documents among `ids`, best match first,
  # and the function giving the snippet segments of a body for this query.
  # A new searcher sees the last commit.
  defp search_hits(index, query, ids, tag_id) do
    with {:ok, parser} <- Query.parser(index, ["title", "body"]),
         {:ok, query} <- parse_query(parser, query),
         {:ok, readable} <- Query.parse(parser, "id: IN [#{Enum.join(ids, " ")}]"),
         {:ok, filters} <- tag_filter(tag_id),
         {:ok, filtered} <- Query.boolean([query, readable | filters], [], []),
         {:ok, searcher} <- Searcher.new(index),
         {:ok, hits} <- Searcher.search(searcher, filtered, @limit) do
      snippet = fn body ->
        case Searcher.snippet(searcher, query, "body", body, max_num_chars: @snippet_length) do
          {:ok, snippet} -> Snippet.segments(body, snippet)
          {:error, _reason} -> nil
        end
      end

      {:ok, Enum.map(hits, &{&1["id"], &1["body"] || ""}), snippet}
    end
  end

  defp tag_filter(nil), do: {:ok, []}

  defp tag_filter(tag_id) do
    with {:ok, tagged} <- Query.term(schema(), "tags", tag_id), do: {:ok, [tagged]}
  end

  # The query, or any of the words starting with its last word.
  # Apostrophes become spaces: Tantivy reads them as quotes, so that
  # "l'association" would be a syntax error. The tokenizer splits words there
  # anyway.
  defp parse_query(parser, query) do
    query = String.replace(query, "'", " ")

    with {:ok, parsed} <- Query.parse(parser, query) do
      case prefix_queries(query) do
        [] -> {:ok, parsed}
        prefixes -> Query.boolean([], [parsed | prefixes], [])
      end
    end
  end

  # The last word, unless it is part of the query syntax (quotes, `field:`,
  # `-`...). Analyzed like the indexed
  # words, whose stems it starts ("associa" gives "associ", the stem of
  # "association"); a word whose stem is not its start is not found that way
  # ("chevau", "cheval" for "chevaux").
  defp prefix_queries(query) do
    word = query |> String.split(~r/\s/u) |> List.last()

    if String.match?(word, ~r/^[\p{L}\p{N}]+$/u) do
      schema = schema()

      for prefix <- Tokenizer.tokenize_text(@tokenizer, word),
          String.length(prefix) >= @prefix_min_length,
          field <- ["title", "body"],
          {:ok, query} <- [Query.phrase_prefix(schema, field, [prefix])] do
        query
      end
    else
      []
    end
  end

  defp load_documents([], _user), do: []

  defp load_documents(ids, user) do
    documents = user |> Document.list_documents(ids) |> Map.new(&{&1.id, &1})

    # a document may have been deleted, or made unreadable, since the search
    ids |> Enum.map(&documents[&1]) |> Enum.reject(&is_nil/1)
  end
end
