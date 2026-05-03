# Tapestry Live Engine — Implementation Plan

> **Goal:** Transform Tapestry from a monolithic serialized-graph library into a **streaming graph engine** backed by DB persistence, incremental sync via `Yog.Builder.Live`, and a visibility protocol that controls what subgraph gets materialized per view context.

## Architecture Overview

```
┌──────────────┐     ┌───────────────┐     ┌──────────────────┐
│   Ecto/DB    │────▶│  Tapestry.Stream  │────▶│  Tapestry.Engine     │
│              │     │               │     │  (GenServer)     │
│  nodes table │     │  • load/2     │     │                  │
│  edges table │     │  • visibility │     │  • Live builder  │
│  comments    │     │    filtering  │     │  • Multi.Graph   │
│  reactions   │     │  • field      │     │  • pending queue │
│              │     │    selection  │     │                  │
│  (PK/FK,     │     └───────────────┘     │  • sync/analyze  │
│   indexed,   │                           │  • PubSub diffs  │
│   queryable) │◀──── persist ◀───────────│                  │
└──────────────┘     individual rows       └────────┬─────────┘
                                                    │
                                           ┌────────▼─────────┐
                                           │  Tapestry.Viewable   │
                                           │  (Protocol)      │
                                           │                  │
                                           │  • visibility/1  │
                                           │  • transform/2   │
                                           │  • render/2      │
                                           └──────────────────┘
```

## Key Design Decisions

1. **DB is source of truth** — Ecto tables store nodes, edges, and heavy data. The graph is a materialized computation window, not the persistence layer.
2. **`Yog.Builder.Live` as the sync engine** — Pending queue tracks deltas, `sync/2` applies in O(ΔE), label registry maps DB PKs to graph node IDs.
3. **Visibility protocol controls loading** — Different views load different subgraphs. Kanban never loads comments. Critical path analysis never loads user names.
4. **Transitions as PubSub diffs** — Mutations broadcast typed transitions; each LiveView filters by its visibility spec and selectively syncs.
5. **Comments as nodes, reactions as edges** — Comments have identity and relationships (threading, authorship). Reactions are lightweight user→target associations.

---

## Phase 1: DB Schema & Ecto Models

**Goal:** Define the relational schema that serves as the source of truth.

### Files

#### `[NEW] lib/tapestry/schema/node.ex`

Ecto schema for graph nodes. All node types share one table with a `:type` discriminator.

```elixir
defmodule Tapestry.Schema.Node do
  use Ecto.Schema

  schema "loom_nodes" do
    field :project_id, :binary_id
    field :ref, :string           # human-readable ID (e.g., "PROJ-123", "design")
    field :type, Ecto.Enum, values: [:task, :milestone, :user, :label, :comment]

    # Common fields (nullable based on type)
    field :title, :string
    field :status, Ecto.Enum, values: [:backlog, :todo, :in_progress, :in_review, :done, :cancelled]
    field :priority, Ecto.Enum, values: [:low, :medium, :high, :critical]
    field :estimate_hours, :float
    field :start_date, :date
    field :due_date, :date

    # User-specific
    field :name, :string
    field :email, :string

    # Comment-specific
    field :body, :string
    field :preview, :string       # truncated body for graph-resident data

    timestamps()
  end
end
```

> **Design note:** Single-table inheritance keeps queries simple and avoids JOINs for mixed-type listings. The tradeoff is nullable columns per type. If this feels wrong, split into `loom_tasks`, `loom_milestones`, etc. with a union view — but STI is simpler for a graph-native model where cross-type queries are common.

#### `[NEW] lib/tapestry/schema/edge.ex`

```elixir
defmodule Tapestry.Schema.Edge do
  use Ecto.Schema

  schema "loom_edges" do
    field :project_id, :binary_id
    field :from_node_id, :id
    field :to_node_id, :id
    field :type, Ecto.Enum, values: [
      :contains, :depends_on, :blocks, :assigned_to,
      :tagged_with, :relates_to, :commented_on, :authored_by, :reply_to
    ]

    # Reaction data (only for :reacted_to edges)
    field :emoji, :string

    timestamps()
  end
end
```

> **Reactions are edges**, not nodes. A reaction is `user --(:reacted_to, emoji: "👍")--> comment`. This avoids graph bloat (thousands of reaction nodes) while keeping them queryable.

#### `[NEW] lib/tapestry/schema/reaction.ex` (optional, alternative)

If you want reactions to be more than edge metadata (e.g., toggle on/off, count aggregation), a dedicated lightweight table may be cleaner:

```elixir
defmodule Tapestry.Schema.Reaction do
  use Ecto.Schema

  schema "loom_reactions" do
    field :project_id, :binary_id
    field :user_node_id, :id
    field :target_node_id, :id
    field :emoji, :string
    timestamps(updated_at: false)
  end
end
```

This keeps reactions out of the graph entirely — they become a UI concern, not a structural one.

#### `[NEW] priv/repo/migrations/..._create_loom_tables.exs`

Standard migration. Key indexes:
- `loom_nodes`: `(project_id, type)`, `(project_id, status)` for cross-project queries
- `loom_edges`: `(project_id, type)`, `(from_node_id)`, `(to_node_id)` for graph loading
- Unique constraint on `(project_id, ref)` for nodes — no duplicate refs within a project

### Open Questions

- [ ] Should `ref` be user-supplied (like `:design`) or auto-generated UUIDs? User-supplied is nicer for the Tapestry API but requires uniqueness enforcement.
- [ ] Do we need `actual_hours` in the schema? It's in the README but might be a v2 concern.

---

## Phase 2: Visibility Protocol & Spec

**Goal:** Define the protocol that controls what subgraph gets materialized.

### Files

#### `[NEW] lib/tapestry/visibility.ex`

```elixir
defmodule Tapestry.Visibility do
  @moduledoc """
  Describes what subgraph to load from the database.

  Used by `Tapestry.Stream` to construct filtered queries and by
  the `Tapestry.Viewable` protocol to declare what each view needs.
  """

  defstruct [
    :root,           # root node ref to scope from (e.g., milestone ref)
    :depth,          # max edge hops from root (nil = unlimited)
    node_types: [],  # which node types to load (empty = all)
    edge_types: [],  # which edge types to load (empty = all)
    fields: [],      # which node fields to select (empty = all)
    exclude_fields: [:body]  # fields to exclude by default (e.g., comment bodies)
  ]

  @type t :: %__MODULE__{
    root: term() | nil,
    depth: non_neg_integer() | nil,
    node_types: [atom()],
    edge_types: [atom()],
    fields: [atom()],
    exclude_fields: [atom()]
  }
end
```

#### `[NEW] lib/tapestry/viewable.ex`

```elixir
defprotocol Tapestry.Viewable do
  @moduledoc """
  Protocol for view specifications that control graph materialization.

  Implementors declare what subgraph they need (visibility),
  how to transform it (filter/annotate), and how to render it.

  Inspired by Choreo's view + viewable pattern.
  """

  @doc "Returns the Visibility spec for this view"
  @spec visibility(t()) :: Tapestry.Visibility.t()
  def visibility(view)

  @doc "Transforms the loaded Tapestry graph (filter, reshape, annotate)"
  @spec transform(t(), Tapestry.t()) :: Tapestry.t()
  def transform(view, tapestry)

  @doc "Renders the transformed graph into output"
  @spec render(t(), Tapestry.t()) :: term()
  def render(view, tapestry)
end
```

#### Predefined View Specs

Each existing view gets a spec struct + protocol implementation:

```elixir
# [NEW] lib/tapestry/view/kanban_spec.ex
defmodule Tapestry.View.KanbanSpec do
  defstruct [:milestone, :assignee, :label, :ticket_base_url]
end

defimpl Tapestry.Viewable, for: Tapestry.View.KanbanSpec do
  def visibility(%{milestone: m}) do
    %Tapestry.Visibility{
      root: m,
      depth: if(m, do: 1, else: nil),
      node_types: [:task, :user],
      edge_types: [:contains, :assigned_to],
      fields: [:title, :status, :priority, :ticket],
      exclude_fields: [:body, :estimate_hours, :start_date, :due_date]
    }
  end

  def transform(spec, tapestry) do
    # Apply assignee/label filters as graph transforms
    tapestry
  end

  def render(_spec, tapestry), do: Tapestry.View.Kanban.to_kanban(tapestry)
end
```

Similar specs for `TimelineSpec`, `GraphSpec`, `TaskDetailSpec`, `AnalysisSpec`.

---

## Phase 3: Tapestry.Stream — DB to Graph Bridge

**Goal:** Load a filtered subgraph from DB using a Visibility spec, returning a `%Tapestry{}` struct.

### Files

#### `[NEW] lib/tapestry/stream.ex`

```elixir
defmodule Tapestry.Stream do
  @moduledoc """
  Bridges Ecto persistence and Tapestry's in-memory graph.

  Loads a filtered subgraph based on a `Tapestry.Visibility` spec,
  using `Yog.Builder.Live` for incremental construction.
  """

  alias Tapestry.Visibility
  alias Yog.Builder.Live, as: LiveBuilder

  @doc """
  Loads a Tapestry project from the database, filtered by visibility.

  Returns `{%Tapestry{}, %LiveBuilder{}}` — the materialized graph
  and the builder (for incremental sync later).
  """
  @spec load(project_id :: term(), Visibility.t(), Ecto.Repo.t()) ::
          {Tapestry.t(), LiveBuilder.t()}
  def load(project_id, %Visibility{} = vis, repo) do
    nodes = query_nodes(project_id, vis, repo)
    edges = query_edges(project_id, vis, MapSet.new(Map.keys(nodes)), repo)

    {builder, graph} = build_graph(nodes, edges)

    tapestry = %Tapestry{
      name: nil,  # loaded separately or from a projects table
      graph: graph
    }

    {tapestry, builder}
  end

  @doc """
  Applies a single transition to an existing Tapestry + builder.

  Used for incremental updates from PubSub broadcasts.
  Returns `{%Tapestry{}, %LiveBuilder{}}`.
  """
  @spec apply_transition(Tapestry.t(), LiveBuilder.t(), transition :: tuple()) ::
          {Tapestry.t(), LiveBuilder.t()}
  def apply_transition(tapestry, builder, transition) do
    # ... queue transition in builder, sync, update tapestry.graph
  end

  # --- Private ---

  defp query_nodes(project_id, vis, repo) do
    # Build Ecto query filtered by:
    # - vis.node_types (WHERE type IN ...)
    # - vis.fields / vis.exclude_fields (SELECT subset)
    # - vis.root + vis.depth (recursive CTE or multi-step BFS)
    # Returns %{node_id => %{type: ..., title: ..., ...}}
  end

  defp query_edges(project_id, vis, node_ids, repo) do
    # Build Ecto query filtered by:
    # - vis.edge_types (WHERE type IN ...)
    # - Both from_node_id and to_node_id IN node_ids
    # Returns [{from_id, to_id, %{type: ..., ...}}]
  end

  defp build_graph(nodes, edges) do
    # Use Yog.Builder.Live to construct the Multi.Graph
    # Label registry maps DB PKs to graph node IDs
  end
end
```

### Key Implementation Details

**Depth-limited loading:** When `vis.root` and `vis.depth` are set, we need to find all nodes within N hops of the root. Two approaches:

1. **Recursive CTE** (Postgres-native, single query):
   ```sql
   WITH RECURSIVE reachable AS (
     SELECT to_node_id AS id, 1 AS depth FROM loom_edges WHERE from_node_id = $root
     UNION
     SELECT e.to_node_id, r.depth + 1 FROM loom_edges e JOIN reachable r ON e.from_node_id = r.id
     WHERE r.depth < $max_depth
   )
   SELECT * FROM loom_nodes WHERE id IN (SELECT id FROM reachable)
   ```

2. **Multi-step BFS** (simpler, multiple queries):
   - Query edges from root → get level-1 node IDs
   - Query edges from level-1 → get level-2 node IDs
   - Repeat up to depth
   - Load all discovered node IDs

Start with option 2 (simpler), optimize to option 1 if performance matters.

**Field selection:** The `vis.fields` and `vis.exclude_fields` control which columns are SELECTed. Comment bodies (`vis.exclude_fields: [:body]`) are skipped unless the view explicitly requests them.

---

## Phase 4: Tapestry.Engine — GenServer with Live Builder

**Goal:** A per-project GenServer that holds the materialized graph, handles mutations via Live builder, and broadcasts transitions via PubSub.

### Files

#### `[NEW] lib/tapestry/engine.ex`

```elixir
defmodule Tapestry.Engine do
  @moduledoc """
  Per-project GenServer that manages a live Tapestry graph.

  Holds a `Yog.Builder.Live` builder and the current `%Tapestry{}` graph.
  Mutations are persisted to DB, queued in the builder, and broadcast
  as transitions via PubSub.

  LiveView processes subscribe to a project's PubSub topic and
  selectively sync transitions that match their visibility spec.
  """

  use GenServer

  defstruct [:project_id, :tapestry, :builder, :repo, :pubsub]

  # --- Client API ---

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    GenServer.start_link(__MODULE__, opts, name: via(project_id))
  end

  def add_task(project_id, ref, attrs),
    do: GenServer.call(via(project_id), {:add_task, ref, attrs})

  def add_dependency(project_id, task_ref, dep_ref),
    do: GenServer.call(via(project_id), {:add_dependency, task_ref, dep_ref})

  def move_task(project_id, task_ref, new_status),
    do: GenServer.call(via(project_id), {:move_task, task_ref, new_status})

  def add_comment(project_id, task_ref, user_ref, body),
    do: GenServer.call(via(project_id), {:add_comment, task_ref, user_ref, body})

  def react(project_id, user_ref, target_ref, emoji),
    do: GenServer.call(via(project_id), {:react, user_ref, target_ref, emoji})

  # Query delegates (read from in-memory graph)
  def ready(project_id), do: GenServer.call(via(project_id), :ready)
  def critical_path(project_id, opts \\ []),
    do: GenServer.call(via(project_id), {:critical_path, opts})
  def validate(project_id), do: GenServer.call(via(project_id), :validate)

  # View rendering
  def render_view(project_id, %view_spec{}),
    do: GenServer.call(via(project_id), {:render_view, view_spec})

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    repo = Keyword.fetch!(opts, :repo)
    pubsub = Keyword.fetch!(opts, :pubsub)

    # Load full graph on init (no visibility filter for the engine)
    full_vis = %Tapestry.Visibility{node_types: [], edge_types: []}
    {tapestry, builder} = Tapestry.Stream.load(project_id, full_vis, repo)

    {:ok, %__MODULE__{
      project_id: project_id,
      tapestry: tapestry,
      builder: builder,
      repo: repo,
      pubsub: pubsub
    }}
  end

  @impl true
  def handle_call({:add_task, ref, attrs}, _from, state) do
    # 1. Persist to DB
    {:ok, node} = persist_node(state.repo, state.project_id, ref, :task, attrs)

    # 2. Queue in builder + sync
    builder = Yog.Builder.Live.add_edge(state.builder, ...)
    {builder, graph} = Yog.Builder.Live.sync(builder, state.tapestry.graph)

    # 3. Broadcast transition
    broadcast(state, {:node_added, :task, ref, attrs})

    {:reply, :ok, %{state | builder: builder, tapestry: %{state.tapestry | graph: graph}}}
  end

  # ... similar handlers for other mutations

  defp broadcast(state, transition) do
    Phoenix.PubSub.broadcast(state.pubsub, "tapestry:#{state.project_id}", transition)
  end

  defp via(project_id), do: {:via, Registry, {Tapestry.Registry, project_id}}
end
```

### LiveView Integration Pattern

```elixir
defmodule MyAppWeb.KanbanLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(%{"project_id" => pid}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, "tapestry:#{pid}")
    end

    spec = %Tapestry.View.KanbanSpec{milestone: nil}
    vis = Tapestry.Viewable.visibility(spec)

    # Load only what this view needs
    {tapestry, builder} = Tapestry.Stream.load(pid, vis, MyApp.Repo)
    rendered = Tapestry.Viewable.render(spec, tapestry)

    {:ok, assign(socket,
      project_id: pid,
      spec: spec,
      tapestry: tapestry,
      builder: builder,
      kanban: rendered
    )}
  end

  @impl true
  def handle_info({:node_added, :task, _ref, _attrs} = transition, socket) do
    # This transition matches our visibility (tasks are in our spec)
    {tapestry, builder} = Tapestry.Stream.apply_transition(
      socket.assigns.tapestry,
      socket.assigns.builder,
      transition
    )

    rendered = Tapestry.Viewable.render(socket.assigns.spec, tapestry)
    {:noreply, assign(socket, tapestry: tapestry, builder: builder, kanban: rendered)}
  end

  def handle_info({:node_added, :comment, _, _}, socket) do
    # Comments are NOT in our Kanban visibility — ignore
    {:noreply, socket}
  end
end
```

---

## Phase 5: Comment & Reaction Support

**Goal:** Add comment and reaction primitives to Tapestry's builder and query layers.

### Files to modify

#### `[MODIFY] lib/tapestry/builder.ex`

Add:
```elixir
def add_comment(tapestry, id, opts \\ [])
def comment_on(tapestry, comment_id, target_id)
def authored_by(tapestry, comment_id, user_id)
def reply_to(tapestry, reply_id, parent_id)
def react(tapestry, user_id, target_id, opts)  # edge-based, not node
```

Validation:
- `comment_on`: comment must be `:comment`, target must be `:task` or `:comment`
- `authored_by`: first must be `:comment`, second must be `:user`
- `reply_to`: both must be `:comment`
- `react`: user must be `:user`, target must exist

#### `[MODIFY] lib/tapestry/query.ex`

Add:
```elixir
def comments(tapestry, target_id)      # all comments on a task/comment
def comment_author(tapestry, comment_id)
def thread(tapestry, root_comment_id)   # recursive walk via reply_to
def reactions(tapestry, target_id)      # edge query, returns [{user_id, emoji}]
```

#### `[MODIFY] lib/tapestry.ex`

Add delegates for new builder/query functions.

#### `[NEW] lib/tapestry/view/task_detail_spec.ex`

A view spec that loads EVERYTHING for one task: the task itself, its comments (with bodies), comment authors, reactions, dependencies.

```elixir
defmodule Tapestry.View.TaskDetailSpec do
  defstruct [:task_ref]
end

defimpl Tapestry.Viewable, for: Tapestry.View.TaskDetailSpec do
  def visibility(%{task_ref: ref}) do
    %Tapestry.Visibility{
      root: ref,
      depth: 3,  # task → comments → replies → authors
      node_types: [:task, :comment, :user],
      edge_types: [:commented_on, :authored_by, :reply_to, :depends_on, :assigned_to],
      fields: [],          # all fields
      exclude_fields: []   # include body for task detail
    }
  end
  # ...
end
```

---

## Phase 6: Multi.Graph Adapter for Live Builder

**Goal:** Bridge `Yog.Builder.Live` (which targets simple `Yog.Graph`) with `Yog.Multi.Graph` (which Tapestry uses).

### The Problem

`Yog.Builder.Live.sync/2` calls `Yog.Model.add_edge/4` which works on simple graphs. Tapestry uses `Yog.Multi.add_edge/4` which returns `{graph, edge_id}` — different API.

### Options

1. **Wrapper module** `Tapestry.LiveSync` that reimplements `apply_transitions` for Multi.Graph:

```elixir
# [NEW] lib/tapestry/live_sync.ex
defmodule Tapestry.LiveSync do
  @moduledoc """
  Applies Yog.Builder.Live transitions to a Yog.Multi.Graph.
  """

  def sync(builder, multi_graph) do
    case builder.pending do
      [] -> {builder, multi_graph}
      pending ->
        transitions = Enum.reverse(pending)
        new_graph = apply_transitions(multi_graph, transitions)
        {%{builder | pending: []}, new_graph}
    end
  end

  defp apply_transitions(graph, transitions) do
    Enum.reduce(transitions, graph, fn
      {:add_node, id, label} ->
        Yog.Multi.add_node(graph, id, label)

      {:add_edge, src, dst, weight} ->
        {graph, _eid} = Yog.Multi.add_edge(graph, src, dst, weight)
        graph

      {:remove_edge, src, dst} ->
        # Multi.Graph needs edge ID — find and remove all edges between src/dst
        remove_all_edges_between(graph, src, dst)

      {:remove_node, id} ->
        Yog.Multi.remove_node(graph, id)
    end)
  end
end
```

2. **Upstream PR to yog_ex** — Add Multi.Graph support to `Yog.Builder.Live` directly. Cleaner long-term.

Start with option 1, contribute option 2 when stable.

---

## Implementation Order

| Step | Phase | Effort | Dependencies |
|------|-------|--------|-------------|
| 1 | Phase 6: LiveSync adapter | 1 hr | None — needed by everything |
| 2 | Phase 2: Visibility + Viewable protocol | 2 hr | None |
| 3 | Phase 3: Tapestry.Stream (DB-less version first, using existing Tapestry structs) | 2 hr | Phase 2 |
| 4 | Phase 5: Comment/reaction builder + query | 2 hr | None |
| 5 | Phase 1: Ecto schemas (only needed when wiring to a real app) | 1 hr | None |
| 6 | Phase 3: Tapestry.Stream (full Ecto version) | 3 hr | Phase 1 |
| 7 | Phase 4: Tapestry.Engine GenServer | 3 hr | Phase 3, 6 |

> **Recommendation:** Do phases 6 → 2 → 3 (DB-less) → 4 first. These are all pure library code with no Ecto dependency — they can live in the `tapestry` package itself. Phases 1, 3 (full), and 7 require a Phoenix app context and should be built in the consuming application or a separate `tapestry_ecto` package.

---

## Testing Strategy

Each phase gets its own test file:

| Phase | Test file | Key assertions |
|-------|-----------|----------------|
| Phase 6 | `test/tapestry/live_sync_test.exs` | Transitions apply to Multi.Graph correctly |
| Phase 2 | `test/tapestry/visibility_test.exs` | Specs filter correctly, protocol dispatches |
| Phase 3 | `test/tapestry/stream_test.exs` | Load → mutate → reload roundtrip |
| Phase 4 | `test/tapestry/engine_test.exs` | GenServer lifecycle, PubSub broadcasts |
| Phase 5 | `test/tapestry/comments_test.exs` | Comment/reaction CRUD, threading, validation |

---

## Package Structure Decision

> **Open question:** Should this stay as one package or split?

| Option | Pros | Cons |
|--------|------|------|
| **Monolith** (`tapestry`) | Simple deps, one repo | Pulls in Ecto/Phoenix for library users who don't need it |
| **Split** (`tapestry` + `tapestry_ecto` + `tapestry_live`) | Clean deps, each package is focused | More repos, version coordination |
| **Core + optional** (`tapestry` with optional Ecto) | One repo, conditional compilation | `Code.ensure_loaded?` checks, harder to test |

**Recommendation:** Keep `tapestry` as the pure library (phases 2, 4, 5, 6). Create `tapestry_ecto` for phases 1, 3, 7 — this depends on `tapestry`, `ecto_sql`, and `phoenix_pubsub`. Consuming Phoenix apps depend on `tapestry_ecto`.
