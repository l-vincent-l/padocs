# The processes of the running application with the longest message queues,
# and their reductions since the last call. Run in the container with
# `bin/padocs rpc`, e.g. during a load test:
#
#   docker exec padocs-loadtest /app/bin/padocs rpc 'Code.eval_file("/loadtest/top.exs")'
top =
  for pid <- Process.list(),
      info = Process.info(pid, [:message_queue_len, :registered_name, :initial_call, :dictionary]),
      info != nil do
    initial =
      case info[:dictionary][:"$initial_call"] do
        {m, f, a} -> "#{inspect(m)}.#{f}/#{a}"
        _ -> inspect(info[:initial_call])
      end

    name = if info[:registered_name] == [], do: initial, else: inspect(info[:registered_name])
    {info[:message_queue_len], name}
  end

queued = top |> Enum.map(&elem(&1, 0)) |> Enum.sum()

IO.puts(
  "processes: #{length(top)}, queued messages: #{queued}, memory: #{div(:erlang.memory(:total), 1_048_576)} MB"
)

top
|> Enum.sort(:desc)
|> Enum.take(5)
|> Enum.each(fn {len, name} -> IO.puts("  #{len}\t#{name}") end)

top
|> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
|> Enum.map(fn {name, lens} -> {Enum.sum(lens), length(lens), name} end)
|> Enum.sort(:desc)
|> Enum.take(3)
|> Enum.each(fn {sum, count, name} ->
  IO.puts("  by kind: #{sum} queued in #{count} × #{name}")
end)
