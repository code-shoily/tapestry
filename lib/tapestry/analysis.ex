defmodule Tapestry.Analysis do
  @moduledoc """
  Graph analysis algorithms for Tapestry projects.

  All functions in this module are available through the `Tapestry` facade.
  See `Tapestry` for usage examples.
  """

  alias Tapestry
  alias Tapestry.Helpers
  alias Tapestry.Query

  @doc """
  Returns tasks with status `:backlog` or `:todo` whose dependencies
  are all `:done`.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_task(:t1, status: :todo)
      iex> [{id, _}] = Tapestry.Analysis.ready(tapestry)
      iex> id
      :t1
  """
  @spec ready(Tapestry.t()) :: [{term(), map()}]
  def ready(%Tapestry{} = tapestry) do
    tapestry
    |> Query.tasks()
    |> Enum.filter(fn {id, data} ->
      data[:status] in [:backlog, :todo] and deps_resolved?(tapestry, id)
    end)
  end

  @doc """
  Returns tasks that have unresolved dependencies or blockers.
  """
  @spec blocked(Tapestry.t()) :: [{term(), map()}]
  def blocked(%Tapestry{} = tapestry) do
    tapestry
    |> Query.tasks()
    |> Enum.filter(fn {id, data} ->
      data[:status] not in [:done, :cancelled] and not deps_resolved?(tapestry, id)
    end)
  end

  @doc """
  Returns tasks with no `:contains` relationship.

  ## Examples

      iex> tapestry = Tapestry.new() |> Tapestry.add_task(:t1)
      iex> [{id, _}] = Tapestry.Analysis.orphans(tapestry)
      iex> id
      :t1
  """
  @spec orphans(Tapestry.t()) :: [{term(), map()}]
  def orphans(%Tapestry{} = tapestry) do
    tapestry
    |> Query.tasks()
    |> Enum.filter(fn {id, _data} -> Query.parent(tapestry, id) == nil end)
  end

  @doc """
  Finds the critical path — the longest chain of dependent work.

  If a `milestone` is given, only tasks under that milestone are considered.

  Returns `{:ok, path, total_estimate}` or `:error` if the dependency graph
  contains a cycle.
  """
  @spec critical_path(Tapestry.t(), keyword()) :: {:ok, [term()], keyword()} | :error
  def critical_path(%Tapestry{} = tapestry, opts \\ []) do
    task_ids =
      case Keyword.get(opts, :milestone) do
        nil ->
          Query.tasks(tapestry) |> Enum.map(fn {id, _} -> id end) |> MapSet.new()

        m_id ->
          Query.children(tapestry, m_id) |> MapSet.new()
      end

    if MapSet.size(task_ids) == 0 do
      {:ok, [], total_estimate: 0}
    else
      dag = weighted_dependency_dag(tapestry, task_ids)

      case Yog.Traversal.Sort.topological_sort(dag) do
        {:ok, sorted} ->
          {dist, pred} =
            Enum.reduce(sorted, {%{}, %{}}, fn node, acc ->
              update_distances(tapestry, dag, node, acc)
            end)

          {end_node, max_dist} =
            task_ids
            |> MapSet.to_list()
            |> Enum.map(fn t -> {t, Map.get(dist, t, 0)} end)
            |> Enum.max_by(fn {_, d} -> d end)

          path = reconstruct_path(pred, end_node)
          {:ok, path, total_estimate: max_dist}

        {:error, :contains_cycle} ->
          :error
      end
    end
  end

  @doc """
  Returns tasks sorted by how many other tasks depend on them
  (directly or transitively).

  High count = task blocks a lot of downstream work (bottleneck).
  """
  @spec bottlenecks(Tapestry.t()) :: [{term(), non_neg_integer()}]
  def bottlenecks(%Tapestry{} = tapestry) do
    dep_graph = dependency_subgraph(tapestry)

    tapestry
    |> Query.tasks()
    |> Enum.map(fn {id, _data} ->
      # Count all nodes reachable from this task via dependency edges
      reachable = Yog.Traversal.walk(dep_graph, id, :breadth_first)
      # exclude self
      count = length(reachable) - 1
      {id, count}
    end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
  end

  @doc """
  Validates structural integrity.

  Returns a list of issues like `{:error, :cycle_detected, nodes}` or
  `{:warning, :unassigned_in_progress, task_id}`.
  """
  @spec validate(Tapestry.t()) :: list()
  def validate(%Tapestry{graph: _g} = tapestry) do
    issues = []

    # Cycles in dependencies
    dep_graph = dependency_subgraph(tapestry)

    issues =
      if Yog.Property.Cyclicity.cyclic?(dep_graph) do
        [{:error, :cycle_detected, cycle_nodes(dep_graph)} | issues]
      else
        issues
      end

    # In-progress tasks without assignees
    issues =
      tapestry
      |> Query.tasks()
      |> Enum.filter(fn {id, data} ->
        data[:status] == :in_progress and Query.assignee(tapestry, id) == nil
      end)
      |> Enum.reduce(issues, fn {id, _data}, acc ->
        [{:warning, :unassigned_in_progress, id} | acc]
      end)

    Enum.reverse(issues)
  end

  # --- Helpers ---

  defp deps_resolved?(%Tapestry{} = tapestry, id) do
    tapestry
    |> Query.dependencies(id)
    |> Enum.all?(fn dep_id ->
      case tapestry.graph.nodes[dep_id] do
        nil -> true
        data -> data[:status] == :done
      end
    end)
  end

  defp reconstruct_path(pred, node, acc \\ []) do
    case Map.get(pred, node) do
      nil -> [node | acc]
      parent -> reconstruct_path(pred, parent, [node | acc])
    end
  end

  defp dependency_subgraph(tapestry) do
    simple = Yog.directed()

    simple =
      Enum.reduce(tapestry.graph.nodes, simple, fn {id, _data}, acc ->
        Yog.Model.add_node(acc, id, nil)
      end)

    Enum.reduce(tapestry.graph.edges, simple, fn {_eid, {from, to, data}}, acc ->
      if data[:type] in [:depends_on, :blocks] do
        case Yog.Model.add_edge(acc, from, to, nil) do
          {:ok, g} -> g
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end

  defp weighted_dependency_dag(tapestry, allowed_nodes) do
    simple = Yog.directed()
    allowed = allowed_nodes

    simple =
      Enum.reduce(tapestry.graph.nodes, simple, fn {id, _data}, acc ->
        if id in allowed do
          Yog.Model.add_node(acc, id, nil)
        else
          acc
        end
      end)

    Enum.reduce(tapestry.graph.edges, simple, fn {_eid, {from, to, data}}, acc ->
      if data[:type] in [:depends_on, :blocks] and from in allowed and to in allowed do
        weight = task_estimate(tapestry, to)

        case Yog.Model.add_edge(acc, from, to, weight) do
          {:ok, g} -> g
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end

  defp update_distances(tapestry, dag, node, {dist_acc, pred_acc}) do
    preds = Helpers.predecessors(dag, node)
    weight = task_estimate(tapestry, node)

    if preds == [] do
      {Map.put(dist_acc, node, weight), pred_acc}
    else
      {best_pred, best_dist} =
        preds
        |> Enum.map(fn p -> {p, Map.get(dist_acc, p, 0) + weight} end)
        |> Enum.max_by(fn {_, d} -> d end)

      {
        Map.put(dist_acc, node, best_dist),
        Map.put(pred_acc, node, best_pred)
      }
    end
  end

  defp task_estimate(%Tapestry{graph: g}, id) do
    case g.nodes[id] do
      %{estimate_hours: hrs} when is_number(hrs) and hrs > 0 -> hrs
      _ -> 1
    end
  end

  defp cycle_nodes(g) do
    case Yog.Traversal.Sort.topological_sort(g) do
      {:ok, _} ->
        []

      {:error, :contains_cycle} ->
        g
        |> Yog.Connectivity.SCC.strongly_connected_components()
        |> Enum.filter(fn comp -> length(comp) > 1 end)
        |> List.flatten()
    end
  end
end
