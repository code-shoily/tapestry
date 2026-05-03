# Tapestry

[![Hex Version](https://img.shields.io/hexpm/v/loom.svg)](https://hex.pm/packages/loom)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/loom/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

> Graph-native task and project management engine for Elixir.

Tapestry models projects, milestones, tasks, users, and labels as nodes in a multigraph.
Relationships — hierarchy, dependencies, assignments — are edges. Kanban boards,
timelines, and dependency networks are projections of the same underlying graph.

No SQL. No foreign keys. No JOINs. Just nodes, edges, and graph algorithms.

```elixir
Tapestry.new("Launch v1")
|> Tapestry.add_milestone(:v1, title: "V1 Launch")
|> Tapestry.add_task(:design, title: "Design", status: :done, estimate_hours: 16)
|> Tapestry.add_task(:impl, title: "Implement", status: :in_progress, estimate_hours: 24)
|> Tapestry.add_task(:test, title: "Test", status: :backlog, estimate_hours: 8)
|> Tapestry.contains(:v1, :design)
|> Tapestry.contains(:v1, :impl)
|> Tapestry.contains(:v1, :test)
|> Tapestry.depends_on(:impl, :design)
|> Tapestry.depends_on(:test, :impl)
|> Tapestry.assign(:design, :alice)
|> Tapestry.add_user(:alice, name: "Alice")

Tapestry.ready(loom)
# => [{:impl, %{...}}, {:test, %{...}}]

Tapestry.critical_path(loom, milestone: :v1)
# => {:ok, [:design, :impl, :test], total_estimate: 48}
```

---

## Table of Contents

- [Why Tapestry?](#why-loom)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Nodes](#nodes)
  - [Edges](#edges)
- [API Overview](#api-overview)
  - [Building](#building)
  - [Querying](#querying)
  - [Analysis](#analysis)
  - [Views](#views)
- [Serialization](#serialization)
- [LiveView & Application Integration](#liveview--application-integration)
- [Development](#development)
- [License](#license)

---

## Why Tapestry?

Traditional task trackers store work in relational tables. Tasks have `parent_id` columns.
Dependencies are stored in a join table. Assignments are another join table. To answer
"what's blocking this?" you write a recursive CTE. To answer "what can we start now?"
you write another.

Tapestry turns the problem inside out: **the graph is the source of truth**.

| Question | SQL way | Tapestry way |
|----------|---------|----------|
| "What blocks this task?" | Recursive CTE on `dependencies` table | `Tapestry.dependencies(loom, :task_id)` |
| "What can we start now?" | Complex status + dependency subquery | `Tapestry.ready(loom)` |
| "Who's overloaded?" | GROUP BY on `assignments` table | `Tapestry.bottlenecks(loom)` |
| "What's the critical path?" | Topological sort in application code | `Tapestry.critical_path(loom)` |
| "Are there circular dependencies?" | Cycle detection algorithm | `Tapestry.validate(loom)` |

Every relationship is explicit, traversable, and validated by graph algorithms.

---

## Installation

Add `loom` to your `mix.exs`:

```elixir
def deps do
  [
    {:loom, "~> 0.1.0"}
  ]
end
```

Tapestry is built on top of [`yog_ex`](https://github.com/code-shoily/yog_ex) and requires Elixir ~> 1.15.

---

## Quick Start

```elixir
alias Tapestry

loom =
  Tapestry.new("Website Redesign")
  |> Tapestry.add_milestone(:v1, title: "V1 Launch", due: ~D[2026-06-01])
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
Tapestry.tasks(loom)                    # All tasks
Tapestry.children(loom, :v1)            # Tasks in milestone
Tapestry.dependencies(loom, :impl)      # What :impl waits on
Tapestry.assignee(loom, :design)        # => :alice

# Analysis
Tapestry.ready(loom)                    # Tasks whose deps are done
Tapestry.blocked(loom)                  # Tasks with unresolved blockers
Tapestry.critical_path(loom, milestone: :v1)
Tapestry.bottlenecks(loom)              # Tasks blocking most downstream work
Tapestry.validate(loom)                 # Structural validation

# Views
Tapestry.to_kanban(loom)                # Mermaid Kanban syntax
Tapestry.to_timeline(loom)              # Mermaid Gantt syntax
Tapestry.to_graph(loom)                 # Mermaid flowchart syntax
```

---

## Core Concepts

### Nodes

| Type | Role | Properties |
|------|------|------------|
| `:task` | Unit of work | `status`, `priority`, `title`, `due_date`, `estimate_hours`, `actual_hours` |
| `:milestone` | Temporal checkpoint | `title`, `due_date` |
| `:user` | Assignee | `name`, `email` |
| `:label` | Categorical tag | `title` |

### Edges

| Type | Direction | Meaning |
|------|-----------|---------|
| `:contains` | parent → child | Hierarchy (milestone → task) |
| `:depends_on` | dependency → task | Task A must finish before task B starts |
| `:blocks` | blocker → blocked | Semantic twin of `:depends_on` |
| `:assigned_to` | task → user | Ownership |
| `:tagged_with` | task → label | Categorization |
| `:relates_to` | bidirectional | Loose association |

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
Tapestry.tasks(loom)                # => [{id, data}, ...]
Tapestry.milestones(loom)
Tapestry.users(loom)
Tapestry.labels(loom)

Tapestry.children(loom, :milestone) # => [task_id, ...]
Tapestry.parent(loom, :task)        # => milestone_id | nil
Tapestry.dependencies(loom, :task)  # => [dep_id, ...]
Tapestry.dependents(loom, :task)    # => [task_id, ...]
Tapestry.assignee(loom, :task)      # => user_id | nil
Tapestry.assigned_tasks(loom, :user)# => [task_id, ...]
```

### Analysis

```elixir
Tapestry.ready(loom)                # Tasks with status backlog/todo and all deps done
Tapestry.blocked(loom)              # Tasks with unresolved dependencies
Tapestry.orphans(loom)              # Tasks not in any milestone

Tapestry.critical_path(loom)                    # Longest dependency chain
Tapestry.critical_path(loom, milestone: :v1)    # Scoped to milestone

Tapestry.bottlenecks(loom)          # Tasks ranked by transitive downstream impact

Tapestry.validate(loom)
# => []  or  [{:error, :cycle_detected, [...]}, {:warning, :unassigned_in_progress, :task_id}]
```

### Views

All views output **Mermaid** syntax, which renders natively in GitHub, GitLab, Notion, Obsidian, and any Mermaid-compatible tool.

#### Kanban

```elixir
Tapestry.to_kanban(loom)
Tapestry.to_kanban(loom, milestone: :v1)
Tapestry.to_kanban(loom, assignee: :alice)
Tapestry.to_kanban(loom, ticket_base_url: "https://jira.company.com/browse/")
```

#### Timeline (Gantt)

```elixir
Tapestry.to_timeline(loom)
Tapestry.to_timeline(loom, milestone: :v1, section_by: :assignee)
Tapestry.to_timeline(loom, start_date: ~D[2026-05-01])
```

Tasks with explicit `start_date` / `due_date` use those. Otherwise, dates are
synthesized from topological order + `estimate_hours`.

#### Dependency Graph

```elixir
Tapestry.to_graph(loom)
Tapestry.to_graph(loom, direction: :lr)
Tapestry.to_graph(loom, milestone: :v1, show_assignments: true)
```

Renders tasks as color-coded boxes (green=done, blue=in-progress, gray=backlog),
milestones as diamonds, and edges as dependency arrows.

---

## Serialization

Tapestry structs are plain data. Serialize however you want:

```elixir
# Erlang term format (fastest, zero deps)
blob = Tapestry.Serializer.to_term(loom)
restored = Tapestry.Serializer.from_term(blob)

# With Jason (if available in your app)
json = Jason.encode!(loom)
```

For persistence, store the binary in Postgres `BYTEA`, Redis, or ETS.
Load on application boot, keep in memory, mutate in place.

---

## LiveView & Application Integration

Tapestry is designed to be the domain model inside a LiveView or GenServer:

```elixir
defmodule MyApp.ProjectServer do
  use GenServer

  def init(project_id) do
    loom = load_from_db(project_id) |> Tapestry.Serializer.from_term()
    {:ok, %{project_id: project_id, loom: loom}}
  end

  def handle_call({:move_task, task_id, status}, _from, state) do
    loom = Tapestry.update_task(state.loom, task_id, status: status)
    :ok = persist(state.project_id, loom)
    {:reply, loom, %{state | loom: loom}}
  end
end
```

Because `%Tapestry{}` is immutable, you get undo/history for free by keeping
previous snapshots. Because it's a graph, structural validation catches
illegal states (cycles, orphans) before they reach your UI.

---

## Development

```bash
# Get dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix coveralls.html

# Type check
mix dialyzer

# Lint
mix credo

# Format
mix format

# Generate docs
mix docs
```

---

## License

MIT License. See [LICENSE](./LICENSE) for details.
