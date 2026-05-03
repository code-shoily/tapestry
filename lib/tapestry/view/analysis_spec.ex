defmodule Tapestry.View.AnalysisSpec do
  @moduledoc """
  View specification for structural analysis operations.

  Unlike rendering views, analysis specs produce data (lists, tuples)
  rather than Mermaid strings. The visibility is minimal — only tasks
  and dependency edges are needed for most analysis operations.

  ## Fields

  - `:operation` — `:ready`, `:blocked`, `:orphans`, `:critical_path`,
    `:bottlenecks`, or `:validate`
  - `:milestone` — scope to tasks within this milestone (for `:critical_path`)
  """

  defstruct [:milestone, operation: :validate]

  @type operation :: :ready | :blocked | :orphans | :critical_path | :bottlenecks | :validate

  @type t :: %__MODULE__{
          operation: operation(),
          milestone: term() | nil
        }
end

defimpl Tapestry.Viewable, for: Tapestry.View.AnalysisSpec do
  def visibility(%{milestone: m}) do
    %Tapestry.Visibility{
      root: m,
      depth: if(m, do: 1, else: nil),
      node_types: [:task, :milestone, :user],
      edge_types: [:depends_on, :blocks, :contains, :assigned_to],
      fields: [:status, :priority, :estimate_hours],
      exclude_fields: []
    }
  end

  def transform(_spec, tapestry), do: tapestry

  def render(spec, tapestry) do
    case spec.operation do
      :ready ->
        Tapestry.Analysis.ready(tapestry)

      :blocked ->
        Tapestry.Analysis.blocked(tapestry)

      :orphans ->
        Tapestry.Analysis.orphans(tapestry)

      :bottlenecks ->
        Tapestry.Analysis.bottlenecks(tapestry)

      :validate ->
        Tapestry.Analysis.validate(tapestry)

      :critical_path ->
        opts = if spec.milestone, do: [milestone: spec.milestone], else: []
        Tapestry.Analysis.critical_path(tapestry, opts)
    end
  end
end
