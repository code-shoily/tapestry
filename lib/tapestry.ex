defmodule Tapestry do
  @moduledoc """
  Graph-native task and project management.

  Tapestry models projects, milestones, tasks, users, and labels as nodes
  in a multigraph. Relationships (hierarchy, dependencies, assignments)
  are edges. Kanban boards, timelines, and dependency networks are
  projections of the same underlying graph.

  ## Quick Start

      iex> alias Tapestry
      iex> tapestry = Tapestry.new("Website Redesign")
      iex> tapestry = Tapestry.add_milestone(tapestry, :v1, title: "V1 Launch")
      iex> tapestry = Tapestry.add_task(tapestry, :design, title: "Design", status: :done)
      iex> tapestry = Tapestry.add_task(tapestry, :impl, title: "Implement", status: :backlog)
      iex> tapestry = Tapestry.contains(tapestry, :v1, :design)
      iex> tapestry = Tapestry.contains(tapestry, :v1, :impl)
      iex> tapestry = Tapestry.depends_on(tapestry, :impl, :design)
      iex> [{id, _}] = Tapestry.ready(tapestry)
      iex> id
      :impl

  ## Architecture

  Tapestry is structured into four layers:

  - **Builder** — `add_task/3`, `depends_on/3`, `assign/3`, etc.
  - **Query** — `tasks/1`, `dependencies/2`, `assignee/2`, etc.
  - **Analysis** — `ready/1`, `critical_path/2`, `bottlenecks/1`, `validate/1`
  - **Views** — `to_kanban/2`, `to_timeline/2`, `to_graph/2`

  All layers operate on the same `%Tapestry{}` struct, which wraps a
  `Yog.Multi.Graph` from `yog_ex`.
  """

  alias Tapestry.{Analysis, Builder, Query}

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

  defdelegate add_task(tapestry, id, opts \\ []), to: Builder
  defdelegate add_milestone(tapestry, id, opts \\ []), to: Builder
  defdelegate add_user(tapestry, id, opts \\ []), to: Builder
  defdelegate add_label(tapestry, id, opts \\ []), to: Builder

  defdelegate update_task(tapestry, id, opts), to: Builder
  defdelegate remove_task(tapestry, id), to: Builder

  defdelegate contains(tapestry, parent, child), to: Builder
  defdelegate depends_on(tapestry, task, dependency), to: Builder
  defdelegate blocks(tapestry, blocker, blocked), to: Builder
  defdelegate assign(tapestry, task, user), to: Builder
  defdelegate tag(tapestry, task, label), to: Builder
  defdelegate relates(tapestry, a, b), to: Builder

  # --- Query delegates ---

  defdelegate tasks(tapestry), to: Query
  defdelegate milestones(tapestry), to: Query
  defdelegate users(tapestry), to: Query
  defdelegate labels(tapestry), to: Query

  defdelegate children(tapestry, id), to: Query
  defdelegate parent(tapestry, id), to: Query
  defdelegate dependencies(tapestry, id), to: Query
  defdelegate dependents(tapestry, id), to: Query
  defdelegate assignee(tapestry, id), to: Query
  defdelegate assigned_tasks(tapestry, user_id), to: Query
  defdelegate tasks_by_status(tapestry, status), to: Query

  # --- Analysis delegates ---

  defdelegate ready(tapestry), to: Analysis
  defdelegate blocked(tapestry), to: Analysis
  defdelegate orphans(tapestry), to: Analysis
  defdelegate validate(tapestry), to: Analysis
  defdelegate critical_path(tapestry, opts \\ []), to: Analysis
  defdelegate bottlenecks(tapestry), to: Analysis

  # --- View delegates ---

  defdelegate to_kanban(tapestry, opts \\ []), to: Tapestry.View.Kanban
  defdelegate to_timeline(tapestry, opts \\ []), to: Tapestry.View.Timeline
  defdelegate to_graph(tapestry, opts \\ []), to: Tapestry.View.Graph

  @doc """
  Renders a view using the `Tapestry.Viewable` protocol.

  Applies the view spec's transform, then renders.
  The visibility spec is available via `Tapestry.Viewable.visibility/1`
  for upstream data loaders to use when materializing the graph.

  ## Example

      iex> tapestry = Tapestry.new("Project")
      iex> spec = %Tapestry.View.KanbanSpec{milestone: :v1}
      iex> Tapestry.render_view(tapestry, spec)
      "kanban\\n"

  """
  @spec render_view(t(), Tapestry.Viewable.t()) :: term()
  def render_view(%__MODULE__{} = tapestry, view_spec) do
    tapestry = Tapestry.Viewable.transform(view_spec, tapestry)
    Tapestry.Viewable.render(view_spec, tapestry)
  end
end
