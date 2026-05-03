# Tapestry

[![Hex Version](https://img.shields.io/hexpm/v/tapestry.svg)](https://hex.pm/packages/tapestry)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/tapestry/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

> A graph-native domain engine for Elixir — model structured domains as typed multigraphs with built-in analysis and visualization.

Tapestry models entities and relationships as nodes and edges in a multigraph.
Kanban boards, timelines, dependency networks, and structural analysis are
all projections of the same underlying graph. Built on [`yog_ex`](https://github.com/code-shoily/yog_ex).

```elixir
project =
  Tapestry.new("Launch v1")
  |> Tapestry.add_milestone(:v1, title: "V1 Launch")
  |> Tapestry.add_task(:design, title: "Design", status: :done, estimate_hours: 16)
  |> Tapestry.add_task(:impl, title: "Implement", status: :in_progress, estimate_hours: 24)
  |> Tapestry.add_task(:test, title: "Test", status: :backlog, estimate_hours: 8)
  |> Tapestry.add_user(:alice, name: "Alice")
  |> Tapestry.contains(:v1, :design)
  |> Tapestry.contains(:v1, :impl)
  |> Tapestry.contains(:v1, :test)
  |> Tapestry.depends_on(:impl, :design)
  |> Tapestry.depends_on(:test, :impl)
  |> Tapestry.assign(:design, :alice)

Tapestry.ready(project)
# => [{:impl, %{status: :in_progress, ...}}]

Tapestry.critical_path(project, milestone: :v1)
# => {:ok, [:design, :impl, :test], total_estimate: 48}
```

---

## Table of Contents

- [Why Tapestry?](#why-tapestry)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [API Overview](#api-overview)
  - [Building](#building)
  - [Querying](#querying)
  - [Analysis](#analysis)
  - [Views](#views)
- [Viewable Protocol](#viewable-protocol)
- [Serialization](#serialization)
- [Architecture](#architecture)
- [Development](#development)
- [License](#license)

---

## Why Tapestry?

Traditional domain tools store entities in relational tables. Dependencies become
join tables. Hierarchy becomes `parent_id` columns. To answer "what's the critical
path?" you write a recursive CTE. To answer "are there circular dependencies?"
you implement cycle detection in application code.

Tapestry turns the problem inside out: **the graph is the domain model**.

| Question | SQL approach | Tapestry |
|----------|-------------|----------|
| What blocks this task? | Recursive CTE on `dependencies` table | `Tapestry.dependencies(project, :task_id)` |
| What can we start now? | Complex status + dependency subquery | `Tapestry.ready(project)` |
| What's the critical path? | Topological sort in application code | `Tapestry.critical_path(project)` |
| Are there circular deps? | Cycle detection algorithm | `Tapestry.validate(project)` |
| Who's the bottleneck? | GROUP BY + recursive reachability | `Tapestry.bottlenecks(project)` |

Every relationship is explicit, traversable, and validated by graph algorithms.

Tapestry is a **pure domain engine** — it defines operations on an in-memory
data structure with no database dependency. Your application decides how to
persist and load the graph (Ecto, ETS, files, etc.).

---

## Installation

Add `tapestry` to your `mix.exs`:

```elixir
def deps do
  [
    {:tapestry, "~> 0.1.0"}
  ]
end
```

Requires Elixir ~> 1.15.

---

## Quick Start

```elixir
project =
  Tapestry.new("Website Redesign")
  |> Tapestry.add_milestone(:v1, title: "V1 Launch")
  |> Tapestry.add_task(:design, title: "Design Homepage", status: :done, priority: :high)
  |> Tapestry.add_task(:impl, title: "Implement Homepage", status: :backlog, estimate_hours: 16)
  |> Tapestry.add_task(:api, title: "Auth API", status: :in_progress, priority: :critical)
  |> Tapestry.add_user(:alice, name: "Alice")
  |> Tapestry.add_label(:frontend)
  |> Tapestry.contains(:v1, :design)
  |> Tapestry.contains(:v1, :impl)
  |> Tapestry.contains(:v1, :api)
  |> Tapestry.depends_on(:impl, :design)
  |> Tapestry.assign(:design, :alice)
  |> Tapestry.tag(:design, :frontend)
  |> Tapestry.tag(:impl, :frontend)

# Query
Tapestry.tasks(project)                    # All tasks
Tapestry.children(project, :v1)            # Tasks in milestone
Tapestry.dependencies(project, :impl)      # What :impl waits on
Tapestry.assignee(project, :design)        # => :alice

# Analysis
Tapestry.ready(project)                    # Tasks whose deps are done
Tapestry.blocked(project)                  # Tasks with unresolved blockers
Tapestry.critical_path(project, milestone: :v1)
Tapestry.bottlenecks(project)              # Tasks blocking most downstream work
Tapestry.validate(project)                 # Structural validation

# Views — all output Mermaid syntax
Tapestry.to_kanban(project)                # Kanban board
Tapestry.to_timeline(project)              # Gantt chart
Tapestry.to_graph(project)                 # Dependency flowchart
```

---

## Core Concepts

### Nodes

| Type | Role | Properties |
|------|------|------------|
| `:task` | Unit of work | `status`, `priority`, `title`, `due_date`, `estimate_hours` |
| `:milestone` | Temporal checkpoint | `title`, `due_date` |
| `:user` | Assignee | `name`, `email` |
| `:label` | Categorical tag | `title` |

### Edges

| Type | Direction | Meaning |
|------|-----------|---------|
| `:contains` | milestone → task | Hierarchy |
| `:depends_on` | dependency → task | Task A must finish before task B starts |
| `:blocks` | blocker → blocked | Semantic twin of `:depends_on` |
| `:assigned_to` | task → user | Ownership |
| `:tagged_with` | task → label | Categorization |
| `:relates_to` | bidirectional | Loose association |

### Validation

All builder functions validate node existence and type at call time:

```elixir
# Raises ArgumentError — :alice is a user, not a milestone
Tapestry.contains(project, :alice, :design)

# Raises ArgumentError — :nonexistent does not exist
Tapestry.depends_on(project, :impl, :nonexistent)
```

---

## API Overview

### Building

```elixir
Tapestry.new("Project Name")
|> Tapestry.add_task(:task_id, title: "Task", status: :backlog, priority: :medium)
|> Tapestry.add_milestone(:milestone_id, title: "Milestone")
|> Tapestry.add_user(:user_id, name: "Alice")
|> Tapestry.add_label(:label_id, title: "frontend")

# Relationships
|> Tapestry.contains(:milestone_id, :task_id)
|> Tapestry.depends_on(:task_b, :task_a)
|> Tapestry.blocks(:bug_7, :feature_5)
|> Tapestry.assign(:task_id, :user_id)
|> Tapestry.tag(:task_id, :label_id)
|> Tapestry.relates(:task_a, :task_b)

# Mutation
|> Tapestry.update_task(:task_id, status: :in_progress)
|> Tapestry.remove_task(:task_id)
```

### Querying

```elixir
Tapestry.tasks(project)                # => [{id, data}, ...]
Tapestry.milestones(project)
Tapestry.users(project)
Tapestry.labels(project)

Tapestry.children(project, :milestone) # => [task_id, ...]
Tapestry.parent(project, :task)        # => milestone_id | nil
Tapestry.dependencies(project, :task)  # => [dep_id, ...]
Tapestry.dependents(project, :task)    # => [task_id, ...]
Tapestry.assignee(project, :task)      # => user_id | nil
Tapestry.assigned_tasks(project, :user)# => [task_id, ...]
```

### Analysis

```elixir
Tapestry.ready(project)                # Tasks with all deps done
Tapestry.blocked(project)              # Tasks with unresolved dependencies
Tapestry.orphans(project)              # Tasks not in any milestone

Tapestry.critical_path(project)                    # Longest dependency chain
Tapestry.critical_path(project, milestone: :v1)    # Scoped to milestone

Tapestry.bottlenecks(project)          # Tasks ranked by transitive downstream impact

Tapestry.validate(project)
# => []  or  [{:error, :cycle_detected, [...]}, {:warning, :unassigned_in_progress, :task_id}]
```

### Views

All views output **Mermaid** syntax — renders natively in GitHub, GitLab, Notion, Obsidian, and any Mermaid-compatible tool.

#### Kanban

```elixir
Tapestry.to_kanban(project)
Tapestry.to_kanban(project, milestone: :v1)
Tapestry.to_kanban(project, assignee: :alice)
Tapestry.to_kanban(project, ticket_base_url: "https://jira.company.com/browse/")
```

#### Timeline (Gantt)

```elixir
Tapestry.to_timeline(project)
Tapestry.to_timeline(project, milestone: :v1, section_by: :assignee)
Tapestry.to_timeline(project, start_date: ~D[2026-05-01])
```

Tasks with explicit `start_date` / `due_date` use those. Otherwise, dates are
synthesized from topological order + `estimate_hours`.

#### Dependency Graph

```elixir
Tapestry.to_graph(project)
Tapestry.to_graph(project, direction: :lr)
Tapestry.to_graph(project, milestone: :v1, show_assignments: true)
```

Renders tasks as color-coded boxes (green=done, blue=in-progress, gray=backlog),
milestones as diamonds, and edges as labeled dependency arrows.

---

## Viewable Protocol

Tapestry includes a `Viewable` protocol for declarative view specifications.
Each view spec declares what data it needs (via `Visibility`) and how to render it.

```elixir
# Struct-based specs replace keyword opts
spec = %Tapestry.View.KanbanSpec{milestone: :v1, assignee: :alice}

# Visibility tells upstream loaders what subgraph to materialize
vis = Tapestry.Viewable.visibility(spec)
# => %Tapestry.Visibility{
#      root: :v1, depth: 1,
#      node_types: [:task, :milestone, :user, :label],
#      edge_types: [:contains, :assigned_to, :tagged_with],
#      fields: [:title, :status, :priority, ...]
#    }

# Render through the facade
Tapestry.render_view(project, spec)
```

Built-in specs: `KanbanSpec`, `TimelineSpec`, `GraphSpec`, `AnalysisSpec`.

Implement your own by defining a struct and the `Tapestry.Viewable` protocol:

```elixir
defmodule MyApp.BurndownSpec do
  defstruct [:milestone, :start_date]
end

defimpl Tapestry.Viewable, for: MyApp.BurndownSpec do
  def visibility(%{milestone: m}) do
    %Tapestry.Visibility{
      root: m,
      node_types: [:task],
      edge_types: [:contains, :depends_on],
      fields: [:status, :estimate_hours]
    }
  end

  def transform(_spec, project), do: project
  def render(_spec, project), do: compute_burndown(project)
end
```

---

## Serialization

`%Tapestry{}` structs are plain data. Serialize however you want:

```elixir
# Erlang term format (fastest, zero deps)
blob = Tapestry.Serializer.to_term(project)
restored = Tapestry.Serializer.from_term(blob)
```

`from_term/1` validates that the deserialized value is a `%Tapestry{}` struct.

---

## Architecture

Tapestry is structured into five layers, all operating on the same `%Tapestry{}` struct:

```
┌──────────────────────────────────────────────┐
│              Tapestry Facade                 │
│  new/1 · add_task/3 · ready/1 · to_kanban/2 │
├──────────┬──────────┬───────────┬────────────┤
│ Builder  │  Query   │ Analysis  │   Views    │
│          │          │           │            │
│ add_task │ tasks    │ ready     │ to_kanban  │
│ contains │ children │ blocked   │ to_timeline│
│ assign   │ parent   │ critical  │ to_graph   │
│ tag      │ assignee │  _path    │            │
├──────────┴──────────┴───────────┴────────────┤
│              Viewable Protocol               │
│  visibility/1 · transform/2 · render/2       │
├──────────────────────────────────────────────┤
│          %Tapestry{graph: Yog.Multi.Graph}   │
└──────────────────────────────────────────────┘
```

Tapestry is a **pure domain engine** with no database, framework, or IO
dependencies. Your application provides persistence and transport:

- **LiveView/GenServer** — hold `%Tapestry{}` in process state
- **Ecto** — store nodes/edges in tables, build the graph on load
- **ETF blob** — serialize to a `BYTEA` column for simple persistence

The `Viewable` protocol enables view-driven data loading — each view
declares what subgraph it needs, so your data layer can load only
the relevant nodes and edges.

---

## Development

```bash
mix deps.get       # Get dependencies
mix test           # Run tests
mix coveralls.html # Coverage report
mix dialyzer       # Type check
mix credo          # Lint
mix format         # Format
mix docs           # Generate docs
```

---

## License

MIT License. See [LICENSE](./LICENSE) for details.
