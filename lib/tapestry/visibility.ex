defmodule Tapestry.Visibility do
  @moduledoc """
  Describes what subgraph to materialize from a data source.

  A `Visibility` spec is a declarative filter that controls which
  node types, edge types, and fields are loaded into a `%Tapestry{}` struct.
  This enables views to load only the data they need — a Kanban board
  never loads comment bodies, and a critical path analysis never loads
  user names.

  ## Usage

  Visibility specs are typically produced by `Tapestry.Viewable` protocol
  implementations, but can also be constructed directly:

      iex> vis = %Tapestry.Visibility{
      ...>   node_types: [:task, :milestone],
      ...>   edge_types: [:depends_on, :blocks, :contains],
      ...>   fields: [:title, :status, :estimate_hours]
      ...> }
      iex> vis.node_types
      [:task, :milestone]

      iex> vis = %Tapestry.Visibility{
      ...>   root: :v1,
      ...>   depth: 1,
      ...>   node_types: [:task],
      ...>   edge_types: [:contains]
      ...> }
      iex> vis.root
      :v1
      iex> vis.depth
      1

  ## Field Selection

  The `fields` and `exclude_fields` options control which node properties
  are included. When `fields` is non-empty, only those fields (plus `:type`)
  are included. When empty, all fields are included except those in
  `exclude_fields`.

  This is particularly useful for comment nodes where the `:body` field
  can be large — exclude it by default and only load it in detail views.
  """

  defstruct [
    :root,
    :depth,
    node_types: [],
    edge_types: [],
    fields: [],
    exclude_fields: []
  ]

  @type t :: %__MODULE__{
          root: term() | nil,
          depth: non_neg_integer() | nil,
          node_types: [atom()],
          edge_types: [atom()],
          fields: [atom()],
          exclude_fields: [atom()]
        }

  @doc """
  Returns true if this visibility includes the given node type.

  An empty `node_types` list means all types are included.

  ## Examples

      iex> vis = %Tapestry.Visibility{node_types: [:task]}
      iex> Tapestry.Visibility.includes_node_type?(vis, :task)
      true
      iex> Tapestry.Visibility.includes_node_type?(vis, :user)
      false
      iex> Tapestry.Visibility.includes_node_type?(%Tapestry.Visibility{}, :user)
      true
  """
  @spec includes_node_type?(t(), atom()) :: boolean()
  def includes_node_type?(%__MODULE__{node_types: []}, _type), do: true
  def includes_node_type?(%__MODULE__{node_types: types}, type), do: type in types

  @doc """
  Returns true if this visibility includes the given edge type.

  An empty `edge_types` list means all types are included.

  ## Examples

      iex> vis = %Tapestry.Visibility{edge_types: [:depends_on]}
      iex> Tapestry.Visibility.includes_edge_type?(vis, :depends_on)
      true
      iex> Tapestry.Visibility.includes_edge_type?(vis, :contains)
      false
  """
  @spec includes_edge_type?(t(), atom()) :: boolean()
  def includes_edge_type?(%__MODULE__{edge_types: []}, _type), do: true
  def includes_edge_type?(%__MODULE__{edge_types: types}, type), do: type in types

  @doc """
  Returns true if this visibility includes the given field.

  When `fields` is non-empty, only those fields are included.
  When `fields` is empty, all fields except `exclude_fields` are included.
  The `:type` field is always included.

  ## Examples

      iex> vis = %Tapestry.Visibility{fields: [:title]}
      iex> Tapestry.Visibility.includes_field?(vis, :title)
      true
      iex> Tapestry.Visibility.includes_field?(vis, :status)
      false
      iex> Tapestry.Visibility.includes_field?(vis, :type)
      true

      iex> vis = %Tapestry.Visibility{exclude_fields: [:body]}
      iex> Tapestry.Visibility.includes_field?(vis, :title)
      true
      iex> Tapestry.Visibility.includes_field?(vis, :body)
      false
  """
  @spec includes_field?(t(), atom()) :: boolean()
  def includes_field?(_vis, :type), do: true
  def includes_field?(%__MODULE__{fields: [_ | _]} = vis, field), do: field in vis.fields
  def includes_field?(%__MODULE__{fields: [], exclude_fields: ex}, field), do: field not in ex

  @doc """
  Filters a node's data map according to this visibility's field rules.

  ## Examples

      iex> vis = %Tapestry.Visibility{fields: [:title]}
      iex> Tapestry.Visibility.filter_fields(vis, %{type: :task, title: "A", body: "B"})
      %{type: :task, title: "A"}
  """
  @spec filter_fields(t(), map()) :: map()
  def filter_fields(%__MODULE__{fields: [], exclude_fields: []} = _vis, data), do: data

  def filter_fields(%__MODULE__{} = vis, data) do
    Map.filter(data, fn {key, _val} -> includes_field?(vis, key) end)
  end

  @doc """
  Returns a visibility that includes everything (no filtering).

  ## Examples

      iex> vis = Tapestry.Visibility.all()
      iex> vis.node_types
      []
  """
  @spec all() :: t()
  def all, do: %__MODULE__{}
end
