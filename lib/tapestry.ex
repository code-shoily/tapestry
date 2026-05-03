defmodule Tapestry do
  @moduledoc """
  Graph-native task and project management.

  Tapestry models projects, milestones, tasks, users, and labels as nodes
  in a multigraph. Relationships (hierarchy, dependencies, assignments)
  are edges. Kanban boards, timelines, and dependency networks are
  projections of the same underlying graph.

  ## Quick Start

      alias Tapestry

      loom =
        Tapestry.new("Website Redesign")
        |> Tapestry.add_milestone(:v1, title: "V1 Launch")
        |> Tapestry.add_task(:design, title: "Design", status: :done)
        |> Tapestry.add_task(:impl, title: "Implement", status: :backlog)
        |> Tapestry.contains(:v1, :design)
        |> Tapestry.contains(:v1, :impl)
        |> Tapestry.depends_on(:impl, :design)

      Tapestry.ready(loom)
      # => [{:impl, %{status: :backlog, ...}}]

  ## Architecture

  Tapestry is structured into four layers:

  - **Builder** — `add_task/3`, `depends_on/3`, `assign/3`, etc.
  - **Query** — `tasks/1`, `dependencies/2`, `assignee/2`, etc.
  - **Analysis** — `ready/1`, `critical_path/2`, `bottlenecks/1`, `validate/1`
  - **Views** — `to_kanban/2`, `to_timeline/2`, `to_graph/2`

  All layers operate on the same `%Tapestry{}` struct, which wraps a
  `Yog.Multi.Graph` from `yog_ex`.
  """

  alias Tapestry.{Builder, Query, Analysis}

  defstruct [:graph, :name]

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          name: String.t() | nil
        }

  @doc """
  Creates a new empty Tapestry project.
  """
  @spec new(String.t() | nil) :: t()
  def new(name \\ nil) do
    %__MODULE__{
      name: name,
      graph: Yog.Multi.directed()
    }
  end

  # --- Builder delegates ---

  defdelegate add_task(loom, id, opts \\ []), to: Builder
  defdelegate add_milestone(loom, id, opts \\ []), to: Builder
  defdelegate add_user(loom, id, opts \\ []), to: Builder
  defdelegate add_label(loom, id, opts \\ []), to: Builder

  defdelegate update_task(loom, id, opts), to: Builder
  defdelegate remove_task(loom, id), to: Builder

  defdelegate contains(loom, parent, child), to: Builder
  defdelegate depends_on(loom, task, dependency), to: Builder
  defdelegate blocks(loom, blocker, blocked), to: Builder
  defdelegate assign(loom, task, user), to: Builder
  defdelegate tag(loom, task, label), to: Builder
  defdelegate relates(loom, a, b), to: Builder

  # --- Query delegates ---

  defdelegate tasks(loom), to: Query
  defdelegate milestones(loom), to: Query
  defdelegate users(loom), to: Query
  defdelegate labels(loom), to: Query

  defdelegate children(loom, id), to: Query
  defdelegate parent(loom, id), to: Query
  defdelegate dependencies(loom, id), to: Query
  defdelegate dependents(loom, id), to: Query
  defdelegate assignee(loom, id), to: Query
  defdelegate assigned_tasks(loom, user_id), to: Query
  defdelegate tasks_by_status(loom, status), to: Query

  # --- Analysis delegates ---

  defdelegate ready(loom), to: Analysis
  defdelegate blocked(loom), to: Analysis
  defdelegate orphans(loom), to: Analysis
  defdelegate validate(loom), to: Analysis
  defdelegate critical_path(loom, opts \\ []), to: Analysis
  defdelegate bottlenecks(loom), to: Analysis

  # --- View delegates ---

  defdelegate to_kanban(loom, opts \\ []), to: Tapestry.View.Kanban
  defdelegate to_timeline(loom, opts \\ []), to: Tapestry.View.Timeline
  defdelegate to_graph(loom, opts \\ []), to: Tapestry.View.Graph

  @doc """
  Renders a view using the `Tapestry.Viewable` protocol.

  Applies the view spec's transform, then renders.
  The visibility spec is available via `Tapestry.Viewable.visibility/1`
  for upstream data loaders to use when materializing the graph.

  ## Example

      spec = %Tapestry.View.KanbanSpec{milestone: :v1}
      Tapestry.render_view(loom, spec)
  """
  @spec render_view(t(), Tapestry.Viewable.t()) :: term()
  def render_view(%__MODULE__{} = loom, view_spec) do
    loom = Tapestry.Viewable.transform(view_spec, loom)
    Tapestry.Viewable.render(view_spec, loom)
  end
end
