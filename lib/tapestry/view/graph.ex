defmodule Tapestry.View.Graph do
  @moduledoc """
  Dependency flowchart projections of a Tapestry project as Mermaid diagrams.

  Renders tasks, milestones, and their relationships as a Mermaid
  flowchart (`graph TD` or `graph LR`).
  """

  alias Tapestry
  alias Tapestry.Helpers
  alias Tapestry.Query

  @status_colors %{
    done: "#4ade80",
    in_progress: "#60a5fa",
    backlog: "#e5e7eb",
    todo: "#fcd34d",
    in_review: "#c084fc",
    cancelled: "#f87171"
  }

  @doc """
  Generates a Mermaid flowchart string showing the project graph.

  ## Options

  - `:direction` — `:td` (top-down, default) or `:lr` (left-right)
  - `:milestone` — Only include tasks under this milestone
  - `:show_contains` — Include `:contains` edges (default `true`)
  - `:show_assignments` — Include `:assigned_to` edges (default `false`)
  - `:show_labels` — Include `:tagged_with` edges (default `false`)
  - `:show_relations` — Include `:relates_to` edges (default `false`)
  """
  @spec to_graph(Tapestry.t(), keyword()) :: String.t()
  def to_graph(%Tapestry{} = loom, opts \\ []) do
    direction = Keyword.get(opts, :direction, :td)
    dir_str = if direction == :lr, do: "LR", else: "TD"

    task_ids =
      case Keyword.get(opts, :milestone) do
        nil -> nil
        m_id -> Query.children(loom, m_id) |> MapSet.new()
      end

    nodes = collect_nodes(loom, task_ids)
    edges = collect_edges(loom, task_ids, opts)

    header = ["graph #{dir_str}"]

    # Node definitions
    node_lines =
      Enum.map(nodes, fn {id, type, label, _status} ->
        shape = node_shape(type)
        "    #{Helpers.sanitize_id(id)}#{shape[:open]}#{escape(label)}#{shape[:close]}"
      end)

    # Style definitions
    style_lines =
      nodes
      |> Enum.filter(fn {_id, type, _label, status} -> type == :task and status end)
      |> Enum.map(fn {id, _type, _label, status} ->
        color = Map.get(@status_colors, status, "#e5e7eb")
        "    style #{Helpers.sanitize_id(id)} fill:#{color},stroke:#333,stroke-width:1px"
      end)

    # Edges
    edge_lines =
      Enum.map(edges, fn {from, to, style, label} ->
        arrow = arrow_style(style)

        if label do
          "    #{Helpers.sanitize_id(from)} #{arrow}|#{label}| #{Helpers.sanitize_id(to)}"
        else
          "    #{Helpers.sanitize_id(from)} #{arrow} #{Helpers.sanitize_id(to)}"
        end
      end)

    (header ++ node_lines ++ style_lines ++ edge_lines)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # --- Node collection ---

  defp collect_nodes(loom, nil) do
    task_nodes =
      Query.tasks(loom)
      |> Enum.map(fn {id, data} ->
        {id, :task, data[:title] || inspect(id), data[:status]}
      end)

    milestone_nodes =
      Query.milestones(loom)
      |> Enum.map(fn {id, data} ->
        {id, :milestone, data[:title] || inspect(id), nil}
      end)

    task_nodes ++ milestone_nodes
  end

  defp collect_nodes(loom, allowed) do
    collect_nodes(loom, nil)
    |> Enum.filter(fn {id, type, _label, _status} ->
      type == :milestone or id in allowed
    end)
  end

  # --- Edge collection ---

  defp collect_edges(loom, task_ids, opts) do
    _show_contains = Keyword.get(opts, :show_contains, true)
    _show_assignments = Keyword.get(opts, :show_assignments, false)
    _show_labels = Keyword.get(opts, :show_labels, false)
    _show_relations = Keyword.get(opts, :show_relations, false)

    loom.graph.edges
    |> Enum.flat_map(fn {_eid, {from, to, data}} ->
      allowed? = task_ids == nil or from in task_ids or to in task_ids

      if allowed? do
        edge_to_mermaid(data[:type], from, to, opts)
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  defp edge_to_mermaid(:depends_on, from, to, _opts), do: [{from, to, :solid, "depends on"}]
  defp edge_to_mermaid(:blocks, from, to, _opts), do: [{from, to, :solid, "blocks"}]

  defp edge_to_mermaid(:contains, from, to, opts) do
    if Keyword.get(opts, :show_contains, true), do: [{from, to, :dashed, nil}], else: []
  end

  defp edge_to_mermaid(:assigned_to, from, to, opts) do
    if Keyword.get(opts, :show_assignments, false), do: [{from, to, :dotted, nil}], else: []
  end

  defp edge_to_mermaid(:tagged_with, from, to, opts) do
    if Keyword.get(opts, :show_labels, false), do: [{from, to, :dotted, nil}], else: []
  end

  defp edge_to_mermaid(:relates_to, from, to, opts) do
    if Keyword.get(opts, :show_relations, false), do: [{from, to, :dashed, nil}], else: []
  end

  defp edge_to_mermaid(_, _from, _to, _opts), do: []

  # --- Shapes ---

  defp node_shape(:task), do: %{open: "[", close: "]"}
  defp node_shape(:milestone), do: %{open: "{", close: "}"}
  defp node_shape(:user), do: %{open: "((", close: "))"}
  defp node_shape(:label), do: %{open: "([", close: "])"}
  defp node_shape(_), do: %{open: "[", close: "]"}

  # --- Arrow styles ---

  defp arrow_style(:solid), do: "-->"
  defp arrow_style(:dashed), do: "-.->"
  defp arrow_style(:dotted), do: "-.->"
  defp arrow_style(_), do: "-->"

  # --- Helpers ---

  defp escape(str) do
    str
    |> Helpers.escape()
    |> String.replace("[", "(")
    |> String.replace("]", ")")
  end
end
