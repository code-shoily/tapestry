# Loom

[![Hex Version](https://img.shields.io/hexpm/v/loom.svg)](https://hex.pm/packages/loom)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/loom/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

> Graph-native task and project management engine for Elixir.

Loom models projects, milestones, tasks, users, and labels as nodes in a multigraph.
Relationships — hierarchy, dependencies, assignments — are edges. Kanban boards,
timelines, and dependency networks are projections of the same underlying graph.

No SQL. No foreign keys. No JOINs. Just nodes, edges, and graph algorithms.

```elixir
Loom.new("Launch v1")
|> Loom.add_milestone(:v1, title: "V1 Launch")
|> Loom.add_task(:design, title: "Design", status: :done, estimate_hours: 16)
|> Loom.add_task(:impl, title: "Implement", status: :in_progress, estimate_hours: 24)
|> Loom.add_task(:test, title: "Test", status: :backlog, estimate_hours: 8)
|> Loom.contains(:v1, :design)
|> Loom.contains(:v1, :impl)
|> Loom.contains(:v1, :test)
|> Loom.depends_on(:impl, :design)
|> Loom.depends_on(:test, :impl)
|> Loom.assign(:design, :alice)
|> Loom.add_user(:alice, name: "Alice")

Loom.ready(loom)
# => [{:impl, %{...}}, {:test, %{...}}]

Loom.critical_path(loom, milestone: :v1)
# => {:ok, [:design, :impl, :test], total_estimate: 48}
```

---

## Table of Contents

- [Why Loom?](#why-loom)
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

## Why Loom?

Traditional task trackers store work in relational tables. Tasks have `parent_id` columns.
Dependencies are stored in a join table. Assignments are another join table. To answer
"what's blocking this?" you write a recursive CTE. To answer "what can we start now?"
you write another.

Loom turns the problem inside out: **the graph is the source of truth**.

| Question | SQL way | Loom way |
|----------|---------|----------|
| "What blocks this task?" | Recursive CTE on `dependencies` table | `Loom.dependencies(loom, :task_id)` |
| "What can we start now?" | Complex status + dependency subquery | `Loom.ready(loom)` |
| "Who's overloaded?" | GROUP BY on `assignments` table | `Loom.bottlenecks(loom)` |
| "What's the critical path?" | Topological sort in application code | `Loom.critical_path(loom)` |
| "Are there circular dependencies?" | Cycle detection algorithm | `Loom.validate(loom)` |

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

Loom is built on top of [`yog_ex`](https://github.com/code-shoily/yog_ex) and requires Elixir ~> 1.15.

---

## Quick Start

```elixir
alias Loom

loom =
  Loom.new("Website Redesign")
  |> Loom.add_milestone(:v1, title: "V1 Launch", due: ~D[2026-06-01])
  |> Loom.add_task(:design, title: "Design Homepage", status: :done, priority: :high)
  |> Loom.add_task(:impl, title: "Implement Homepage", status: :backlog, estimate_hours: 16)
  |> Loom.add_task(:api, title: "Auth API", status: :in_progress, priority: :critical)
  |> Loom.add_user(:alice, name: "Alice")
  |> Loom.add_label(:frontend)
  |> Loom.contains(:v1, :design)
  |> Loom.contains(:v1, :impl)
  |> Loom.contains(:v1, :api)
  |> Loom.depends_on(:impl, :design)
  |> Loom.assign(:design, :alice)
  |> Loom.tag(:design, :frontend)
  |> Loom.tag(:impl, :frontend)

# Query
Loom.tasks(loom)                    # All tasks
Loom.children(loom, :v1)            # Tasks in milestone
Loom.dependencies(loom, :impl)      # What :impl waits on
Loom.assignee(loom, :design)        # => :alice

# Analysis
Loom.ready(loom)                    # Tasks whose deps are done
Loom.blocked(loom)                  # Tasks with unresolved blockers
Loom.critical_path(loom, milestone: :v1)
Loom.bottlenecks(loom)              # Tasks blocking most downstream work
Loom.validate(loom)                 # Structural validation

# Views
Loom.to_kanban(loom)                # Mermaid Kanban syntax
Loom.to_timeline(loom)              # Mermaid Gantt syntax
Loom.to_graph(loom)                 # Mermaid flowchart syntax
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
Loom.new("Project Name")
|> Loom.add_task(:task_id, title: "Task", status: :backlog, priority: :medium)
|> Loom.add_milestone(:milestone_id, title: "Milestone")
|> Loom.add_user(:user_id, name: "Alice")
|> Loom.add_label(:label_id, title: "frontend")

# Relationships
|> Loom.contains(:milestone_id, :task_id)
|> Loom.depends_on(:task_b, :task_a)
|> Loom.blocks(:bug_7, :feature_5)
|> Loom.assign(:task_id, :user_id)
|> Loom.tag(:task_id, :label_id)
|> Loom.relates(:task_a, :task_b)

# Mutation
|> Loom.update_task(:task_id, status: :in_progress)
|> Loom.remove_task(:task_id)
```

### Querying

```elixir
Loom.tasks(loom)                # => [{id, data}, ...]
Loom.milestones(loom)
Loom.users(loom)
Loom.labels(loom)

Loom.children(loom, :milestone) # => [task_id, ...]
Loom.parent(loom, :task)        # => milestone_id | nil
Loom.dependencies(loom, :task)  # => [dep_id, ...]
Loom.dependents(loom, :task)    # => [task_id, ...]
Loom.assignee(loom, :task)      # => user_id | nil
Loom.assigned_tasks(loom, :user)# => [task_id, ...]
```

### Analysis

```elixir
Loom.ready(loom)                # Tasks with status backlog/todo and all deps done
Loom.blocked(loom)              # Tasks with unresolved dependencies
Loom.orphans(loom)              # Tasks not in any milestone

Loom.critical_path(loom)                    # Longest dependency chain
Loom.critical_path(loom, milestone: :v1)    # Scoped to milestone

Loom.bottlenecks(loom)          # Tasks ranked by transitive downstream impact

Loom.validate(loom)
# => []  or  [{:error, :cycle_detected, [...]}, {:warning, :unassigned_in_progress, :task_id}]
```

### Views

All views output **Mermaid** syntax, which renders natively in GitHub, GitLab, Notion, Obsidian, and any Mermaid-compatible tool.

#### Kanban

```elixir
Loom.to_kanban(loom)
Loom.to_kanban(loom, milestone: :v1)
Loom.to_kanban(loom, assignee: :alice)
Loom.to_kanban(loom, ticket_base_url: "https://jira.company.com/browse/")
```

#### Timeline (Gantt)

```elixir
Loom.to_timeline(loom)
Loom.to_timeline(loom, milestone: :v1, section_by: :assignee)
Loom.to_timeline(loom, start_date: ~D[2026-05-01])
```

Tasks with explicit `start_date` / `due_date` use those. Otherwise, dates are
synthesized from topological order + `estimate_hours`.

#### Dependency Graph

```elixir
Loom.to_graph(loom)
Loom.to_graph(loom, direction: :lr)
Loom.to_graph(loom, milestone: :v1, show_assignments: true)
```

Renders tasks as color-coded boxes (green=done, blue=in-progress, gray=backlog),
milestones as diamonds, and edges as dependency arrows.

---

## Serialization

Loom structs are plain data. Serialize however you want:

```elixir
# Erlang term format (fastest, zero deps)
blob = Loom.Serializer.to_term(loom)
restored = Loom.Serializer.from_term(blob)

# With Jason (if available in your app)
json = Jason.encode!(loom)
```

For persistence, store the binary in Postgres `BYTEA`, Redis, or ETS.
Load on application boot, keep in memory, mutate in place.

---

## LiveView & Application Integration

Loom is designed to be the domain model inside a LiveView or GenServer:

```elixir
defmodule MyApp.ProjectServer do
  use GenServer

  def init(project_id) do
    loom = load_from_db(project_id) |> Loom.Serializer.from_term()
    {:ok, %{project_id: project_id, loom: loom}}
  end

  def handle_call({:move_task, task_id, status}, _from, state) do
    loom = Loom.update_task(state.loom, task_id, status: status)
    :ok = persist(state.project_id, loom)
    {:reply, loom, %{state | loom: loom}}
  end
end
```

Because `%Loom{}` is immutable, you get undo/history for free by keeping
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
