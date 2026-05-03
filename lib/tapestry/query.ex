defmodule Tapestry.Query do
  @moduledoc """
  Graph traversal and query API for Tapestry projects.

  All functions in this module are available through the `Tapestry` facade.
  See `Tapestry` for usage examples.
  """

  alias Tapestry

  @doc """
  Returns all task nodes.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_task(:t1, title: "T1")
      iex> [{id, _}] = Tapestry.Query.tasks(tapestry)
      iex> id
      :t1
  """
  @spec tasks(Tapestry.t()) :: [{term(), map()}]
  def tasks(%Tapestry{graph: g}), do: nodes_of_type(g, :task)

  @doc """
  Returns all milestone nodes.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_milestone(:v1, title: "V1")
      iex> [{id, _}] = Tapestry.Query.milestones(tapestry)
      iex> id
      :v1
  """
  @spec milestones(Tapestry.t()) :: [{term(), map()}]
  def milestones(%Tapestry{graph: g}), do: nodes_of_type(g, :milestone)

  @doc """
  Returns all user nodes.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_user(:alice, name: "Alice")
      iex> [{_id, data}] = Tapestry.Query.users(tapestry)
      iex> data.name
      "Alice"
  """
  @spec users(Tapestry.t()) :: [{term(), map()}]
  def users(%Tapestry{graph: g}), do: nodes_of_type(g, :user)

  @doc """
  Returns all label nodes.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_label(:frontend, title: "Frontend")
      iex> [{_id, data}] = Tapestry.Query.labels(tapestry)
      iex> data.title
      "Frontend"
  """
  @spec labels(Tapestry.t()) :: [{term(), map()}]
  def labels(%Tapestry{graph: g}), do: nodes_of_type(g, :label)

  @doc """
  Returns tasks filtered by status.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_task(:a, status: :done) |> Tapestry.add_task(:b, status: :backlog)
      iex> [{id, _}] = Tapestry.Query.tasks_by_status(tapestry, :done)
      iex> id
      :a
  """
  @spec tasks_by_status(Tapestry.t(), atom()) :: [{term(), map()}]
  def tasks_by_status(%Tapestry{graph: g}, status) do
    g.nodes
    |> Enum.filter(fn {_id, data} -> data[:type] == :task and data[:status] == status end)
    |> Enum.map(fn {id, data} -> {id, data} end)
  end

  @doc """
  Returns child node IDs for a given node (connected via `:contains` edge).

  ## Examples

      iex> tapestry = Tapestry.new()
      iex> tapestry = Tapestry.add_milestone(tapestry, :m1)
      iex> tapestry = Tapestry.add_task(tapestry, :t1)
      iex> tapestry = Tapestry.contains(tapestry, :m1, :t1)
      iex> Tapestry.Query.children(tapestry, :m1)
      [:t1]
  """
  @spec children(Tapestry.t(), term()) :: [term()]
  def children(%Tapestry{graph: g}, id) do
    g
    |> outgoing_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] == :contains end)
    |> Enum.map(fn {_eid, _from, to, _data} -> to end)
  end

  @doc """
  Returns the parent node ID for a given node (connected via `:contains` edge).

  ## Examples

      iex> tapestry = Tapestry.new()
      iex> tapestry = Tapestry.add_milestone(tapestry, :m1)
      iex> tapestry = Tapestry.add_task(tapestry, :t1)
      iex> tapestry = Tapestry.contains(tapestry, :m1, :t1)
      iex> Tapestry.Query.parent(tapestry, :t1)
      :m1
  """
  @spec parent(Tapestry.t(), term()) :: term() | nil
  def parent(%Tapestry{graph: g}, id) do
    g
    |> incoming_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] == :contains end)
    |> Enum.map(fn {_eid, from, _to, _data} -> from end)
    |> List.first()
  end

  @doc """
  Returns the IDs of nodes that `id` depends on.

  Includes both `:depends_on` and `:blocks` edges.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_task(:a) |> Tapestry.add_task(:b) |> Tapestry.depends_on(:b, :a)
      iex> Tapestry.Query.dependencies(tapestry, :b)
      [:a]
  """
  @spec dependencies(Tapestry.t(), term()) :: [term()]
  def dependencies(%Tapestry{graph: g}, id) do
    g
    |> incoming_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] in [:depends_on, :blocks] end)
    |> Enum.map(fn {_eid, from, _to, _data} -> from end)
  end

  @doc """
  Returns the IDs of nodes that depend on `id`.

  Includes both `:depends_on` and `:blocks` edges.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_task(:a) |> Tapestry.add_task(:b) |> Tapestry.depends_on(:b, :a)
      iex> Tapestry.Query.dependents(tapestry, :a)
      [:b]
  """
  @spec dependents(Tapestry.t(), term()) :: [term()]
  def dependents(%Tapestry{graph: g}, id) do
    g
    |> outgoing_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] in [:depends_on, :blocks] end)
    |> Enum.map(fn {_eid, _from, to, _data} -> to end)
  end

  @doc """
  Returns the user ID assigned to a task, or `nil` if unassigned.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_task(:t1) |> Tapestry.add_user(:alice) |> Tapestry.assign(:t1, :alice)
      iex> Tapestry.Query.assignee(tapestry, :t1)
      :alice

      iex> Tapestry.Query.assignee(Tapestry.new() |> Tapestry.add_task(:t1), :t1)
      nil
  """
  @spec assignee(Tapestry.t(), term()) :: term() | nil
  def assignee(%Tapestry{graph: g}, id) do
    g
    |> outgoing_edges(id)
    |> Enum.filter(fn {_eid, _from, _to, data} -> data[:type] == :assigned_to end)
    |> Enum.map(fn {_eid, _from, to, _data} -> to end)
    |> List.first()
  end

  @doc """
  Returns all task IDs assigned to a given user.

  ## Examples

      iex> tapestry = Tapestry.new()
      ...> |> Tapestry.add_task(:t1)
      ...> |> Tapestry.add_task(:t2)
      ...> |> Tapestry.add_user(:alice)
      ...> |> Tapestry.assign(:t1, :alice)
      iex> Tapestry.Query.assigned_tasks(tapestry, :alice)
      [:t1]
  """
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
