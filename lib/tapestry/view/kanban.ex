defmodule Tapestry.View.Kanban do
  @moduledoc """
  Kanban board projections of a Tapestry project as Mermaid Kanban syntax.

  Mermaid Kanban is supported natively in GitHub, GitLab, Notion, and
  any platform that renders Mermaid diagrams.
  """

  alias Tapestry
  alias Tapestry.Helpers
  alias Tapestry.Query

  @status_columns [
    backlog: "Backlog",
    todo: "Todo",
    in_progress: "In Progress",
    in_review: "In Review",
    done: "Done",
    cancelled: "Cancelled"
  ]

  @doc """
  Generates a Mermaid Kanban diagram string.

  ## Options

  - `:milestone` — Only include tasks contained in this milestone.
  - `:assignee` — Only include tasks assigned to this user.
  - `:label` — Only include tasks tagged with this label.
  - `:ticket_base_url` — Base URL for ticket links (e.g. Jira).

  ## Examples

      iex> tapestry = Tapestry.new("Test")
      ...> |> Tapestry.add_task(:a, title: "Task A", status: :done)
      ...> |> Tapestry.add_task(:b, title: "Task B", status: :backlog)
      iex> kanban = Tapestry.View.Kanban.to_kanban(tapestry)
      iex> kanban =~ "kanban"
      true
      iex> kanban =~ "Task A"
      true
  """
  @spec to_kanban(Tapestry.t(), keyword()) :: String.t()
  def to_kanban(%Tapestry{} = tapestry, opts \\ []) do
    tasks = Query.tasks(tapestry)

    tasks =
      Enum.reduce(opts, tasks, fn
        {:milestone, m_id}, acc ->
          ms_children = Query.children(tapestry, m_id) |> MapSet.new()
          Enum.filter(acc, fn {id, _data} -> id in ms_children end)

        {:assignee, user_id}, acc ->
          Enum.filter(acc, fn {id, _data} -> Query.assignee(tapestry, id) == user_id end)

        {:label, label_id}, acc ->
          Enum.filter(acc, fn {id, _data} -> tagged_with?(tapestry, id, label_id) end)

        _, acc ->
          acc
      end)

    ticket_base_url = Keyword.get(opts, :ticket_base_url)

    header =
      if ticket_base_url do
        [
          "---",
          "config:",
          "  kanban:",
          "    ticketBaseUrl: '#{ticket_base_url}'",
          "---",
          "kanban"
        ]
      else
        ["kanban"]
      end

    column_lines =
      Enum.flat_map(@status_columns, fn {status, col_name} ->
        col_tasks = Enum.filter(tasks, fn {_id, data} -> data[:status] == status end)

        if col_tasks == [] do
          []
        else
          col_id = Helpers.sanitize_id("#{status}_col")

          cards =
            Enum.map(col_tasks, fn {id, data} ->
              render_task_card(tapestry, id, data)
            end)

          ["  #{col_id}[#{col_name}]" | cards]
        end
      end)

    (header ++ column_lines)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # --- Helpers ---

  defp render_task_card(tapestry, id, data) do
    name = Helpers.escape(data[:title] || inspect(id))
    task_id = Helpers.sanitize_id(id)
    meta = task_metadata(tapestry, id, data)

    if meta == %{} do
      "    #{task_id}[#{name}]"
    else
      meta_str =
        Enum.map_join(meta, ", ", fn {k, v} -> "#{k}: #{escape_meta(v)}" end)

      "    #{task_id}[#{name}]@{ #{meta_str} }"
    end
  end

  defp task_metadata(tapestry, id, data) do
    %{}
    |> maybe_put(:assigned, assignee_name(tapestry, id))
    |> maybe_put(:priority, mermaid_priority(data[:priority]))
    |> maybe_put(:ticket, data[:ticket])
  end

  defp assignee_name(tapestry, id) do
    case Query.assignee(tapestry, id) do
      nil -> nil
      user_id -> tapestry.graph.nodes[user_id][:name] || inspect(user_id)
    end
  end

  defp mermaid_priority(:critical), do: "Very High"
  defp mermaid_priority(:high), do: "High"
  defp mermaid_priority(:low), do: "Low"
  defp mermaid_priority(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp tagged_with?(%Tapestry{graph: g}, task_id, label_id) do
    eids = Map.get(g.out_edge_ids, task_id, MapSet.new())

    Enum.any?(MapSet.to_list(eids), fn eid ->
      {_from, to, data} = Map.fetch!(g.edges, eid)
      to == label_id and data[:type] == :tagged_with
    end)
  end

  defp escape_meta(str) do
    str = to_string(str)

    if String.contains?(str, ",") or String.contains?(str, ":") do
      "'#{String.replace(str, "'", "\\'")}'"
    else
      str
    end
  end
end
