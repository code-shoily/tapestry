defmodule Tapestry.Helpers do
  @moduledoc false

  # Shared utilities used by view and analysis modules.

  @doc """
  Sanitizes an ID for use in Mermaid diagram identifiers.
  """
  @spec sanitize_id(term()) :: String.t()
  def sanitize_id(id) when is_atom(id), do: Atom.to_string(id)
  def sanitize_id(id) when is_binary(id), do: String.replace(id, ~r/[^a-zA-Z0-9_]/, "_")
  def sanitize_id(id), do: "node_#{inspect(id)}"

  @doc """
  Escapes a string for safe use in Mermaid labels.
  """
  @spec escape(term()) :: String.t()
  def escape(str) do
    str
    |> to_string()
    |> String.replace("\"", "\\\"")
  end

  @doc """
  Returns the predecessor node IDs for a node in a Yog simple graph.
  """
  @spec predecessors(Yog.Graph.t(), term()) :: [term()]
  def predecessors(graph, node) do
    graph
    |> Yog.Model.predecessors(node)
    |> Enum.map(fn {from, _weight} -> from end)
  end

  @doc """
  Builds a simple directed graph containing only dependency edges
  (:depends_on, :blocks) among the allowed set of nodes from a Tapestry multigraph.
  """
  @spec build_restricted_dag(Tapestry.t(), MapSet.t()) :: Yog.Graph.t()
  def build_restricted_dag(%Tapestry{graph: g}, allowed_nodes) do
    simple = Yog.directed()

    simple =
      Enum.reduce(g.nodes, simple, fn {id, _data}, acc ->
        if MapSet.member?(allowed_nodes, id) do
          Yog.Model.add_node(acc, id, nil)
        else
          acc
        end
      end)

    Enum.reduce(g.edges, simple, fn {_eid, {from, to, data}}, acc ->
      if data[:type] in [:depends_on, :blocks] and
           MapSet.member?(allowed_nodes, from) and
           MapSet.member?(allowed_nodes, to) do
        case Yog.Model.add_edge(acc, from, to, nil) do
          {:ok, g} -> g
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end
end
