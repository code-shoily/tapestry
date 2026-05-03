defmodule Tapestry.View.KanbanSpec do
  @moduledoc """
  View specification for Kanban board rendering.

  ## Fields

  - `:milestone` — scope to tasks within this milestone
  - `:assignee` — filter to tasks assigned to this user
  - `:label` — filter to tasks tagged with this label
  - `:ticket_base_url` — base URL for ticket links (e.g. Jira)
  """

  defstruct [:milestone, :assignee, :label, :ticket_base_url]

  @type t :: %__MODULE__{
          milestone: term() | nil,
          assignee: term() | nil,
          label: term() | nil,
          ticket_base_url: String.t() | nil
        }
end

defimpl Tapestry.Viewable, for: Tapestry.View.KanbanSpec do
  def visibility(%{milestone: m}) do
    %Tapestry.Visibility{
      root: m,
      depth: if(m, do: 1, else: nil),
      node_types: [:task, :milestone, :user, :label],
      edge_types: [:contains, :assigned_to, :tagged_with],
      fields: [:title, :status, :priority, :ticket, :name],
      exclude_fields: []
    }
  end

  def transform(_spec, loom), do: loom

  def render(spec, loom) do
    opts =
      []
      |> then(fn o -> if spec.milestone, do: [{:milestone, spec.milestone} | o], else: o end)
      |> then(fn o -> if spec.assignee, do: [{:assignee, spec.assignee} | o], else: o end)
      |> then(fn o -> if spec.label, do: [{:label, spec.label} | o], else: o end)
      |> then(fn o ->
        if spec.ticket_base_url, do: [{:ticket_base_url, spec.ticket_base_url} | o], else: o
      end)

    Tapestry.View.Kanban.to_kanban(loom, opts)
  end
end
