defmodule Tapestry.View.TimelineSpec do
  @moduledoc """
  View specification for Timeline / Gantt chart rendering.

  ## Fields

  - `:milestone` — scope to tasks within this milestone
  - `:section_by` — `:milestone` or `:assignee` (default `:milestone`)
  - `:start_date` — base date for synthetic scheduling
  - `:title` — chart title (defaults to project name)
  """

  defstruct [:milestone, :title, :start_date, section_by: :milestone]

  @type t :: %__MODULE__{
          milestone: term() | nil,
          section_by: :milestone | :assignee,
          start_date: Date.t() | nil,
          title: String.t() | nil
        }
end

defimpl Tapestry.Viewable, for: Tapestry.View.TimelineSpec do
  def visibility(%{milestone: m}) do
    %Tapestry.Visibility{
      root: m,
      depth: if(m, do: 1, else: nil),
      node_types: [:task, :milestone, :user],
      edge_types: [:contains, :depends_on, :blocks, :assigned_to],
      fields: [:title, :status, :priority, :estimate_hours, :start_date, :due_date, :name],
      exclude_fields: []
    }
  end

  def transform(_spec, tapestry), do: tapestry

  def render(spec, tapestry) do
    opts =
      []
      |> then(fn o -> if spec.milestone, do: [{:milestone, spec.milestone} | o], else: o end)
      |> then(fn o -> if spec.title, do: [{:title, spec.title} | o], else: o end)
      |> then(fn o -> if spec.start_date, do: [{:start_date, spec.start_date} | o], else: o end)
      |> then(fn o -> [{:section_by, spec.section_by} | o] end)

    Tapestry.View.Timeline.to_timeline(tapestry, opts)
  end
end
