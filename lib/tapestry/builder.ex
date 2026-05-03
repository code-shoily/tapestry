defmodule Tapestry.Builder do
  @moduledoc """
  Graph construction API for Tapestry projects.

  All functions in this module are available through the `Tapestry` facade.
  See `Tapestry` for usage examples.
  """

  alias Tapestry

  @doc """
  Adds a task node.

  ## Options

  - `:status` — `:backlog` (default), `:todo`, `:in_progress`, `:in_review`, `:done`, `:cancelled`
  - `:priority` — `:low`, `:medium` (default), `:high`, `:critical`
  - `:title`, `:due_date`, `:estimate_hours`, `:actual_hours`, etc.
  """
  @spec add_task(Tapestry.t(), term(), keyword()) :: Tapestry.t()
  def add_task(%Tapestry{graph: g} = loom, id, opts \\ []) do
    data = Map.merge(%{type: :task, status: :backlog, priority: :medium}, Map.new(opts))
    %{loom | graph: Yog.Multi.add_node(g, id, data)}
  end

  @spec add_milestone(Tapestry.t(), term(), keyword()) :: Tapestry.t()
  def add_milestone(%Tapestry{graph: g} = loom, id, opts \\ []) do
    data = Map.merge(%{type: :milestone}, Map.new(opts))
    %{loom | graph: Yog.Multi.add_node(g, id, data)}
  end

  @spec add_user(Tapestry.t(), term(), keyword()) :: Tapestry.t()
  def add_user(%Tapestry{graph: g} = loom, id, opts \\ []) do
    data = Map.merge(%{type: :user}, Map.new(opts))
    %{loom | graph: Yog.Multi.add_node(g, id, data)}
  end

  @spec add_label(Tapestry.t(), term(), keyword()) :: Tapestry.t()
  def add_label(%Tapestry{graph: g} = loom, id, opts \\ []) do
    data = Map.merge(%{type: :label}, Map.new(opts))
    %{loom | graph: Yog.Multi.add_node(g, id, data)}
  end

  @doc """
  Updates an existing task node's properties.

  Merges the given options into the task's current data.
  Raises `ArgumentError` if the node does not exist or is not a task.
  """
  @spec update_task(Tapestry.t(), term(), keyword()) :: Tapestry.t()
  def update_task(%Tapestry{graph: g} = loom, id, opts) do
    require_node!(g, id, :task, "update_task")
    current = Map.fetch!(g.nodes, id)
    %{loom | graph: Yog.Multi.add_node(g, id, Map.merge(current, Map.new(opts)))}
  end

  @doc """
  Removes a task node and all edges connected to it.
  """
  @spec remove_task(Tapestry.t(), term()) :: Tapestry.t()
  def remove_task(%Tapestry{graph: g} = loom, id) do
    %{loom | graph: Yog.Multi.remove_node(g, id)}
  end

  # --- Edges ---

  @doc """
  Parent -> child containment edge.

  The parent must be a milestone and the child must be a task.
  """
  @spec contains(Tapestry.t(), term(), term()) :: Tapestry.t()
  def contains(%Tapestry{graph: g} = loom, parent, child) do
    require_node!(g, parent, :milestone, "contains")
    require_node!(g, child, :task, "contains")
    {graph, _eid} = Yog.Multi.add_edge(g, parent, child, %{type: :contains})
    %{loom | graph: graph}
  end

  @doc """
  Declares that `task` depends on `dependency`.

  Creates an edge `dependency -> task` meaning *dependency must finish
  before task can start*. Both must be tasks.
  """
  @spec depends_on(Tapestry.t(), term(), term()) :: Tapestry.t()
  def depends_on(%Tapestry{graph: g} = loom, task, dependency) do
    require_node!(g, task, :task, "depends_on")
    require_node!(g, dependency, :task, "depends_on")
    {graph, _eid} = Yog.Multi.add_edge(g, dependency, task, %{type: :depends_on})
    %{loom | graph: graph}
  end

  @doc """
  Declares that `blocker` blocks `blocked`.

  Semantically identical to `depends_on/3` but carries intent.
  Both must be tasks.
  """
  @spec blocks(Tapestry.t(), term(), term()) :: Tapestry.t()
  def blocks(%Tapestry{graph: g} = loom, blocker, blocked) do
    require_node!(g, blocker, :task, "blocks")
    require_node!(g, blocked, :task, "blocks")
    {graph, _eid} = Yog.Multi.add_edge(g, blocker, blocked, %{type: :blocks})
    %{loom | graph: graph}
  end

  @doc """
  Assigns a task to a user. Edge: task -> user.

  Raises if `task` is not a task node or `user` is not a user node.
  """
  @spec assign(Tapestry.t(), term(), term()) :: Tapestry.t()
  def assign(%Tapestry{graph: g} = loom, task, user) do
    require_node!(g, task, :task, "assign")
    require_node!(g, user, :user, "assign")
    {graph, _eid} = Yog.Multi.add_edge(g, task, user, %{type: :assigned_to})
    %{loom | graph: graph}
  end

  @doc """
  Tags a task with a label. Edge: task -> label.

  Raises if `task` is not a task node or `label` is not a label node.
  """
  @spec tag(Tapestry.t(), term(), term()) :: Tapestry.t()
  def tag(%Tapestry{graph: g} = loom, task, label) do
    require_node!(g, task, :task, "tag")
    require_node!(g, label, :label, "tag")
    {graph, _eid} = Yog.Multi.add_edge(g, task, label, %{type: :tagged_with})
    %{loom | graph: graph}
  end

  @doc """
  Creates a bidirectional `:relates_to` relationship between two nodes.

  Both nodes must exist.
  """
  @spec relates(Tapestry.t(), term(), term()) :: Tapestry.t()
  def relates(%Tapestry{graph: g} = loom, a, b) do
    require_existing!(g, a, "relates")
    require_existing!(g, b, "relates")
    {g1, _eid1} = Yog.Multi.add_edge(g, a, b, %{type: :relates_to})
    {g2, _eid2} = Yog.Multi.add_edge(g1, b, a, %{type: :relates_to})
    %{loom | graph: g2}
  end

  # --- Validation Helpers ---

  defp require_node!(g, id, expected_type, caller) do
    case Map.get(g.nodes, id) do
      nil ->
        raise ArgumentError,
              "#{caller}: node #{inspect(id)} does not exist"

      data ->
        actual = data[:type]

        if actual != expected_type do
          raise ArgumentError,
                "#{caller}: expected #{inspect(id)} to be a #{expected_type}, got #{actual}"
        end
    end
  end

  defp require_existing!(g, id, caller) do
    unless Map.has_key?(g.nodes, id) do
      raise ArgumentError,
            "#{caller}: node #{inspect(id)} does not exist"
    end
  end
end
