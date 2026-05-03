defmodule Tapestry.View.GraphSpec do
  @moduledoc """
  View specification for dependency flowchart rendering.

  ## Fields

  - `:milestone` — scope to tasks within this milestone
  - `:direction` — `:td` (top-down, default) or `:lr` (left-right)
  - `:show_contains` — include containment edges (default `true`)
  - `:show_assignments` — include assignment edges (default `false`)
  - `:show_labels` — include tag edges (default `false`)
  - `:show_relations` — include relates_to edges (default `false`)
  """

  defstruct [
    :milestone,
    direction: :td,
    show_contains: true,
    show_assignments: false,
    show_labels: false,
    show_relations: false
  ]

  @type t :: %__MODULE__{
          milestone: term() | nil,
          direction: :td | :lr,
          show_contains: boolean(),
          show_assignments: boolean(),
          show_labels: boolean(),
          show_relations: boolean()
        }
end

defimpl Tapestry.Viewable, for: Tapestry.View.GraphSpec do
  def visibility(spec) do
    edge_types =
      [:depends_on, :blocks]
      |> then(fn e -> if spec.show_contains, do: [:contains | e], else: e end)
      |> then(fn e -> if spec.show_assignments, do: [:assigned_to | e], else: e end)
      |> then(fn e -> if spec.show_labels, do: [:tagged_with | e], else: e end)
      |> then(fn e -> if spec.show_relations, do: [:relates_to | e], else: e end)

    node_types =
      [:task, :milestone]
      |> then(fn n -> if spec.show_assignments, do: [:user | n], else: n end)
      |> then(fn n -> if spec.show_labels, do: [:label | n], else: n end)

    %Tapestry.Visibility{
      root: spec.milestone,
      depth: if(spec.milestone, do: 1, else: nil),
      node_types: node_types,
      edge_types: edge_types,
      fields: [:title, :status, :priority, :name],
      exclude_fields: []
    }
  end

  def transform(_spec, tapestry), do: tapestry

  def render(spec, tapestry) do
    opts = [
      direction: spec.direction,
      show_contains: spec.show_contains,
      show_assignments: spec.show_assignments,
      show_labels: spec.show_labels,
      show_relations: spec.show_relations
    ]

    opts =
      if spec.milestone, do: [{:milestone, spec.milestone} | opts], else: opts

    Tapestry.View.Graph.to_graph(tapestry, opts)
  end
end
