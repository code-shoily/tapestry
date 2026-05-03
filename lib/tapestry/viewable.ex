defprotocol Tapestry.Viewable do
  @moduledoc """
  Protocol for view specifications that control graph materialization and rendering.

  Each view in a Tapestry-powered application has different data needs. A Kanban
  board needs tasks and assignments but not comment bodies. A critical path
  analysis needs task estimates and dependencies but not user names.

  The `Viewable` protocol lets view specifications declare:

  1. **What to load** — `visibility/1` returns a `%Tapestry.Visibility{}` spec
  2. **How to transform** — `transform/2` reshapes the loaded graph
  3. **How to render** — `render/2` produces the output format

  ## Example

      spec = %Tapestry.View.KanbanSpec{milestone: :v1, assignee: :alice}

      # In a data loader (e.g., LiveView mount):
      vis = Tapestry.Viewable.visibility(spec)
      loom = load_from_db(project_id, vis)

      # In a render path:
      loom = Tapestry.Viewable.transform(spec, loom)
      output = Tapestry.Viewable.render(spec, loom)

  ## Implementing

  Define a struct for your view's parameters, then implement the protocol:

      defmodule MyApp.BurndownSpec do
        defstruct [:milestone, :start_date]
      end

      defimpl Tapestry.Viewable, for: MyApp.BurndownSpec do
        def visibility(%{milestone: m}) do
          %Tapestry.Visibility{
            root: m,
            node_types: [:task],
            edge_types: [:contains, :depends_on],
            fields: [:status, :estimate_hours, :actual_hours]
          }
        end

        def transform(_spec, loom), do: loom

        def render(spec, loom) do
          # Custom burndown chart logic
        end
      end
  """

  @doc """
  Returns the `%Tapestry.Visibility{}` spec describing what subgraph this view needs.
  """
  @spec visibility(t()) :: Tapestry.Visibility.t()
  def visibility(view)

  @doc """
  Transforms the loaded `%Tapestry{}` graph before rendering.

  Use this for view-specific filtering, annotation, or reshaping
  that goes beyond what `Visibility` covers. For example, a Kanban
  view might filter tasks by assignee here, since that's a graph-level
  filter rather than a load-level filter.

  Return the `%Tapestry{}` unchanged if no transformation is needed.
  """
  @spec transform(t(), Tapestry.t()) :: Tapestry.t()
  def transform(view, loom)

  @doc """
  Renders the transformed `%Tapestry{}` into the view's output format.

  Returns whatever the view produces — a Mermaid string, a map of
  Kanban columns, a list of analysis results, etc.
  """
  @spec render(t(), Tapestry.t()) :: term()
  def render(view, loom)
end
