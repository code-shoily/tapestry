defmodule Tapestry.Query do
  @moduledoc """
  Graph traversal and query API for Tapestry projects.

  All functions in this module are available through the `Tapestry` facade.
  See `Tapestry` for usage examples.
  """

  alias Tapestry

  @spec tasks(Tapestry.t()) :: [{term(), map()}]
  def tasks(%Tapestry{graph: g}), do: nodes_of_type(g, :task)

  @spec milestones(Tapestry.t()) :: [{term(), map()}]
  def milestones(%Tapestry{graph: g}), do: nodes_of_type(g, :milestone)

  @spec users(Tapestry.t()) :: [{term(), map()}]
  def users(%Tapestry{graph: g}), do: nodes_of_type(g, :user)

  @spec labels(Tapestry.t()) :: [{term(), map()}]
  def labels(%Tapestry{graph: g}), do: nodes_of_type(g, :label)

  @spec tasks_by_status(Tapestry.t(), atom()) :: [{term(), map()}]
  def tasks_by_status(%Tapestry{graph: g}, status) do
    g.nodes
    |> Enum.filter(fn {_id, data} -> data[:type] == :task and data[:status] == status end)
    |> Enum.map(fn {id, data} -> {id, data} end)
  end

  @spec children(Tapestry.t(), term()) :: [term()]
  def children(%Tapestry{graph: g}, id) do
    g
    |> outgoing_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] == :contains end)
    |> Enum.map(fn {_eid, _from, to, _data} -> to end)
  end

  @spec parent(Tapestry.t(), term()) :: term() | nil
  def parent(%Tapestry{graph: g}, id) do
    g
    |> incoming_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] == :contains end)
    |> Enum.map(fn {_eid, from, _to, _data} -> from end)
    |> List.first()
  end

  @spec dependencies(Tapestry.t(), term()) :: [term()]
  def dependencies(%Tapestry{graph: g}, id) do
    g
    |> incoming_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] in [:depends_on, :blocks] end)
    |> Enum.map(fn {_eid, from, _to, _data} -> from end)
  end

  @spec dependents(Tapestry.t(), term()) :: [term()]
  def dependents(%Tapestry{graph: g}, id) do
    g
    |> outgoing_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] in [:depends_on, :blocks] end)
    |> Enum.map(fn {_eid, _from, to, _data} -> to end)
  end

  @spec assignee(Tapestry.t(), term()) :: term() | nil
  def assignee(%Tapestry{graph: g}, id) do
    g
    |> outgoing_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] == :assigned_to end)
    |> Enum.map(fn {_eid, _from, to, _data} -> to end)
    |> List.first()
  end

  @spec assigned_tasks(Tapestry.t(), term()) :: [term()]
  def assigned_tasks(%Tapestry{graph: g}, user_id) do
    g
    |> incoming_edges(user_id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] == :assigned_to end)
    |> Enum.map(fn {_eid, from, _to, _data} -> from end)
  end

  # --- Helpers ---

  defp nodes_of_type(g, type) do
    g.nodes
    |> Enum.filter(fn {_id, data} -> data[:type] == type end)
    |> Enum.map(fn {id, data} -> {id, data} end)
  end

  defp outgoing_edges(g, id) do
    eids = Map.get(g.out_edge_ids, id, MapSet.new())

    Enum.map(MapSet.to_list(eids), fn eid ->
      {from, to, data} = Map.fetch!(g.edges, eid)
      {eid, from, to, data}
    end)
  end

  defp incoming_edges(g, id) do
    eids = Map.get(g.in_edge_ids, id, MapSet.new())

    Enum.map(MapSet.to_list(eids), fn eid ->
      {from, to, data} = Map.fetch!(g.edges, eid)
      {eid, from, to, data}
    end)
  end
end
