defmodule TapestryTest do
  use ExUnit.Case

  doctest Tapestry
  doctest Tapestry.Builder
  doctest Tapestry.Query
  doctest Tapestry.Analysis
  doctest Tapestry.Serializer
  doctest Tapestry.Helpers
  doctest Tapestry.View.Kanban
  doctest Tapestry.View.Timeline
  doctest Tapestry.View.Graph

  describe "builder" do
    test "creates a project and adds tasks" do
      tapestry =
        Tapestry.new("Website Redesign")
        |> Tapestry.add_milestone(:v1, title: "V1 Launch")
        |> Tapestry.add_task(:design, title: "Design Homepage", status: :done)
        |> Tapestry.add_task(:impl, title: "Implement Homepage", status: :backlog)
        |> Tapestry.add_user(:alice, name: "Alice")
        |> Tapestry.contains(:v1, :design)
        |> Tapestry.contains(:v1, :impl)
        |> Tapestry.depends_on(:impl, :design)
        |> Tapestry.assign(:design, :alice)

      assert length(Tapestry.tasks(tapestry)) == 2
      assert length(Tapestry.milestones(tapestry)) == 1
      assert Enum.sort(Tapestry.children(tapestry, :v1)) == [:design, :impl]
      assert Tapestry.dependencies(tapestry, :impl) == [:design]
      assert Tapestry.assignee(tapestry, :design) == :alice
      assert Tapestry.assigned_tasks(tapestry, :alice) == [:design]
    end
  end

  describe "kanban view" do
    test "to_kanban/2 generates Mermaid Kanban syntax" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "Task A", status: :done)
        |> Tapestry.add_task(:b, title: "Task B", status: :in_progress)
        |> Tapestry.add_task(:c, title: "Task C", status: :backlog)
        |> Tapestry.add_task(:d, title: "Task D", status: :backlog)

      kanban = Tapestry.to_kanban(tapestry)
      assert String.starts_with?(kanban, "kanban\n")
      assert kanban =~ "Done"
      assert kanban =~ "In Progress"
      assert kanban =~ "Backlog"
      assert kanban =~ "Task A"
      assert kanban =~ "Task B"
    end

    test "to_kanban/2 filters by milestone" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_milestone(:v1)
        |> Tapestry.add_task(:a, title: "In Milestone", status: :backlog)
        |> Tapestry.add_task(:b, title: "Orphan", status: :backlog)
        |> Tapestry.contains(:v1, :a)

      kanban = Tapestry.to_kanban(tapestry, milestone: :v1)
      assert kanban =~ "In Milestone"
      refute kanban =~ "Orphan"
    end

    test "to_kanban/2 includes assignee metadata" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "Alice Task", status: :backlog, priority: :high)
        |> Tapestry.add_user(:alice, name: "Alice")
        |> Tapestry.assign(:a, :alice)

      kanban = Tapestry.to_kanban(tapestry)
      assert kanban =~ "assigned: Alice"
      assert kanban =~ "priority: High"
    end
  end

  describe "timeline view" do
    test "to_timeline/2 generates Mermaid Gantt syntax" do
      tapestry =
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

      gantt = Tapestry.to_timeline(tapestry, start_date: ~D[2026-05-01])

      assert String.starts_with?(gantt, "gantt\n")
      assert gantt =~ "title Launch v1"
      assert gantt =~ "Design"
      assert gantt =~ "Implement"
      assert gantt =~ "Test"
    end

    test "to_timeline/2 respects explicit dates" do
      tapestry =
        Tapestry.new("Dated Project")
        |> Tapestry.add_task(:a,
          title: "Task A",
          start_date: ~D[2026-06-01],
          due_date: ~D[2026-06-05]
        )

      gantt = Tapestry.to_timeline(tapestry)
      assert gantt =~ "2026-06-01"
      assert gantt =~ "5d"
    end

    test "to_timeline/2 sections by assignee" do
      tapestry =
        Tapestry.new("Team Work")
        |> Tapestry.add_task(:a, title: "Alice Task", estimate_hours: 8)
        |> Tapestry.add_task(:b, title: "Bob Task", estimate_hours: 8)
        |> Tapestry.add_user(:alice, name: "Alice")
        |> Tapestry.add_user(:bob, name: "Bob")
        |> Tapestry.assign(:a, :alice)
        |> Tapestry.assign(:b, :bob)

      gantt = Tapestry.to_timeline(tapestry, section_by: :assignee)
      assert gantt =~ "section Alice"
      assert gantt =~ "section Bob"
    end
  end

  describe "critical path" do
    test "finds longest dependency chain" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, estimate_hours: 2)
        |> Tapestry.add_task(:b, estimate_hours: 3)
        |> Tapestry.add_task(:c, estimate_hours: 5)
        |> Tapestry.depends_on(:b, :a)
        |> Tapestry.depends_on(:c, :b)

      assert {:ok, [:a, :b, :c], total_estimate: total} = Tapestry.critical_path(tapestry)
      assert total == 10
    end

    test "finds critical path to a milestone" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_milestone(:v1)
        |> Tapestry.add_task(:a, estimate_hours: 2)
        |> Tapestry.add_task(:b, estimate_hours: 3)
        |> Tapestry.add_task(:c, estimate_hours: 5)
        |> Tapestry.add_task(:d, estimate_hours: 1)
        |> Tapestry.contains(:v1, :a)
        |> Tapestry.contains(:v1, :b)
        |> Tapestry.contains(:v1, :c)
        |> Tapestry.depends_on(:b, :a)
        |> Tapestry.depends_on(:c, :b)

      assert {:ok, [:a, :b, :c], total_estimate: total} =
               Tapestry.critical_path(tapestry, milestone: :v1)

      assert total == 10
    end

    test "returns :error for cyclic dependencies" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)
        |> Tapestry.add_task(:b)
        |> Tapestry.add_task(:c)
        |> Tapestry.depends_on(:b, :a)
        |> Tapestry.depends_on(:a, :c)
        |> Tapestry.depends_on(:c, :b)

      assert :error = Tapestry.critical_path(tapestry)
    end
  end

  describe "bottlenecks" do
    test "identifies tasks on many dependency chains" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:core)
        |> Tapestry.add_task(:a)
        |> Tapestry.add_task(:b)
        |> Tapestry.add_task(:c)
        |> Tapestry.add_task(:x)
        |> Tapestry.add_task(:y)
        |> Tapestry.depends_on(:a, :core)
        |> Tapestry.depends_on(:b, :core)
        |> Tapestry.depends_on(:c, :core)
        |> Tapestry.depends_on(:x, :a)
        |> Tapestry.depends_on(:y, :b)

      bottlenecks = Tapestry.bottlenecks(tapestry)
      {top_id, _score} = hd(bottlenecks)
      assert top_id == :core
    end
  end

  describe "analysis" do
    test "ready/1 returns tasks whose deps are done" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, status: :done)
        |> Tapestry.add_task(:b, status: :backlog)
        |> Tapestry.add_task(:c, status: :backlog)
        |> Tapestry.depends_on(:b, :a)
        |> Tapestry.depends_on(:c, :b)

      ready = Tapestry.ready(tapestry)
      ids = Enum.map(ready, fn {id, _data} -> id end)
      assert :b in ids
      refute :c in ids
    end

    test "validate/1 detects cycles" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)
        |> Tapestry.add_task(:b)
        |> Tapestry.add_task(:c)
        |> Tapestry.depends_on(:b, :a)
        |> Tapestry.depends_on(:a, :c)
        |> Tapestry.depends_on(:c, :b)

      issues = Tapestry.validate(tapestry)
      assert {:error, :cycle_detected, _} = List.first(issues)
    end

    test "validate/1 warns on unassigned in-progress tasks" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, status: :in_progress)

      issues = Tapestry.validate(tapestry)
      assert {:warning, :unassigned_in_progress, :a} in issues
    end
  end

  describe "graph view" do
    test "to_graph/2 generates Mermaid flowchart" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_milestone(:v1, title: "V1")
        |> Tapestry.add_task(:a, title: "Task A", status: :done)
        |> Tapestry.add_task(:b, title: "Task B", status: :in_progress)
        |> Tapestry.add_task(:c, title: "Task C", status: :backlog)
        |> Tapestry.contains(:v1, :a)
        |> Tapestry.contains(:v1, :b)
        |> Tapestry.depends_on(:b, :a)
        |> Tapestry.depends_on(:c, :b)

      graph = Tapestry.to_graph(tapestry)
      assert String.starts_with?(graph, "graph TD\n")
      assert graph =~ "a[Task A]"
      assert graph =~ "b[Task B]"
      assert graph =~ "c[Task C]"
      assert graph =~ "v1{V1}"
      assert graph =~ "a -->|depends on| b"
      assert graph =~ "b -->|depends on| c"
      assert graph =~ "v1 -.-> a"
      assert graph =~ "style a fill:#4ade80"
      assert graph =~ "style b fill:#60a5fa"
    end

    test "to_graph/2 can filter by milestone" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_milestone(:v1)
        |> Tapestry.add_milestone(:v2)
        |> Tapestry.add_task(:a, title: "A")
        |> Tapestry.add_task(:b, title: "B")
        |> Tapestry.contains(:v1, :a)
        |> Tapestry.contains(:v2, :b)

      graph = Tapestry.to_graph(tapestry, milestone: :v1)
      assert graph =~ "A"
      refute graph =~ "B"
    end

    test "to_graph/2 supports left-right direction" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)
        |> Tapestry.add_task(:b)
        |> Tapestry.depends_on(:b, :a)

      graph = Tapestry.to_graph(tapestry, direction: :lr)
      assert String.starts_with?(graph, "graph LR\n")
    end
  end

  describe "serialization" do
    test "to_term/from_term roundtrips a project" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "Task A", status: :done)
        |> Tapestry.add_task(:b, title: "Task B", status: :in_progress)
        |> Tapestry.depends_on(:b, :a)

      blob = Tapestry.Serializer.to_term(tapestry)
      assert is_binary(blob)

      restored = Tapestry.Serializer.from_term(blob)
      assert restored.name == "Test"
      assert length(Tapestry.tasks(restored)) == 2
      assert Tapestry.dependencies(restored, :b) == [:a]
    end
  end

  describe "mutators" do
    test "update_task/3 merges properties" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "Old Title", status: :backlog)
        |> Tapestry.update_task(:a, title: "New Title", status: :in_progress)

      task = Tapestry.tasks(tapestry) |> Enum.find(fn {id, _} -> id == :a end) |> elem(1)
      assert task[:title] == "New Title"
      assert task[:status] == :in_progress
    end

    test "remove_task/2 deletes node and edges" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)
        |> Tapestry.add_task(:b)
        |> Tapestry.depends_on(:b, :a)
        |> Tapestry.remove_task(:a)

      assert length(Tapestry.tasks(tapestry)) == 1
      assert Tapestry.dependencies(tapestry, :b) == []
    end
  end

  describe "orphans" do
    test "returns tasks not in any milestone" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_milestone(:v1)
        |> Tapestry.add_task(:a, title: "In milestone")
        |> Tapestry.add_task(:b, title: "Orphan")
        |> Tapestry.contains(:v1, :a)

      orphans = Tapestry.orphans(tapestry)
      ids = Enum.map(orphans, fn {id, _} -> id end)
      assert :b in ids
      refute :a in ids
    end
  end

  describe "tasks_by_status" do
    test "filters tasks by status" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, status: :done)
        |> Tapestry.add_task(:b, status: :in_progress)
        |> Tapestry.add_task(:c, status: :done)

      done = Tapestry.tasks_by_status(tapestry, :done)
      ids = Enum.map(done, fn {id, _} -> id end)
      assert :a in ids
      assert :c in ids
      refute :b in ids
    end
  end

  describe "blocks" do
    test "blocks/3 creates blocking relationship" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:bug, title: "Bug")
        |> Tapestry.add_task(:feature, title: "Feature")
        |> Tapestry.blocks(:bug, :feature)

      assert :bug in Tapestry.dependencies(tapestry, :feature)
    end
  end

  describe "tag and labels" do
    test "tag/3 creates tagged_with edge" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "Task A")
        |> Tapestry.add_label(:frontend)
        |> Tapestry.tag(:a, :frontend)

      labels = Tapestry.labels(tapestry)
      assert length(labels) == 1
      assert {:frontend, _} = hd(labels)
    end
  end

  describe "relates" do
    test "relates/3 creates bidirectional relationship" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "A")
        |> Tapestry.add_task(:b, title: "B")
        |> Tapestry.relates(:a, :b)

      # Both directions should have relates_to edges
      graph = tapestry.graph

      edge_types =
        graph.edges
        |> Enum.map(fn {_eid, {_from, _to, data}} -> data[:type] end)
        |> Enum.filter(&(&1 == :relates_to))

      assert length(edge_types) == 2
    end
  end

  describe "parent" do
    test "parent/2 returns the containing milestone" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_milestone(:v1, title: "V1")
        |> Tapestry.add_task(:a)
        |> Tapestry.contains(:v1, :a)

      assert Tapestry.parent(tapestry, :a) == :v1
    end

    test "parent/2 returns nil for orphaned tasks" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)

      assert Tapestry.parent(tapestry, :a) == nil
    end
  end

  describe "builder validation" do
    test "contains/3 raises if parent is not a milestone" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)
        |> Tapestry.add_task(:b)

      assert_raise ArgumentError, ~r/expected :a to be a milestone/, fn ->
        Tapestry.contains(tapestry, :a, :b)
      end
    end

    test "depends_on/3 raises if node does not exist" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)

      assert_raise ArgumentError, ~r/does not exist/, fn ->
        Tapestry.depends_on(tapestry, :a, :nonexistent)
      end
    end

    test "assign/3 raises if user is not a user node" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)
        |> Tapestry.add_task(:b)

      assert_raise ArgumentError, ~r/expected :b to be a user/, fn ->
        Tapestry.assign(tapestry, :a, :b)
      end
    end

    test "tag/3 raises if label is not a label node" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a)
        |> Tapestry.add_task(:b)

      assert_raise ArgumentError, ~r/expected :b to be a label/, fn ->
        Tapestry.tag(tapestry, :a, :b)
      end
    end

    test "update_task/3 raises if node does not exist" do
      tapestry = Tapestry.new("Test")

      assert_raise ArgumentError, ~r/does not exist/, fn ->
        Tapestry.update_task(tapestry, :nonexistent, title: "Nope")
      end
    end

    test "update_task/3 raises if node is not a task" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_user(:alice, name: "Alice")

      assert_raise ArgumentError, ~r/expected :alice to be a task/, fn ->
        Tapestry.update_task(tapestry, :alice, name: "Bob")
      end
    end
  end

  describe "serializer validation" do
    test "from_term/1 raises on non-Tapestry binary" do
      blob = :erlang.term_to_binary(%{not: "a tapestry"})

      assert_raise ArgumentError, ~r/expected a Tapestry struct/, fn ->
        Tapestry.Serializer.from_term(blob)
      end
    end
  end

  describe "analysis - blocked" do
    test "blocked/1 excludes done tasks with unresolved deps" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, status: :backlog)
        |> Tapestry.add_task(:b, status: :done)
        |> Tapestry.depends_on(:b, :a)

      blocked = Tapestry.blocked(tapestry)
      ids = Enum.map(blocked, fn {id, _} -> id end)
      refute :b in ids
    end
  end

  describe "graph view - edge labels" do
    test "to_graph/2 renders edge labels for dependency edges" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "A")
        |> Tapestry.add_task(:b, title: "B")
        |> Tapestry.depends_on(:b, :a)

      graph = Tapestry.to_graph(tapestry)
      assert graph =~ "|depends on|"
    end

    test "to_graph/2 renders blocks label" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "A")
        |> Tapestry.add_task(:b, title: "B")
        |> Tapestry.blocks(:a, :b)

      graph = Tapestry.to_graph(tapestry)
      assert graph =~ "|blocks|"
    end
  end

  describe "kanban - ticket_base_url" do
    test "to_kanban/2 includes ticket base URL in frontmatter" do
      tapestry =
        Tapestry.new("Test")
        |> Tapestry.add_task(:a, title: "Task", status: :backlog)

      kanban = Tapestry.to_kanban(tapestry, ticket_base_url: "https://jira.example.com/browse/")
      assert kanban =~ "ticketBaseUrl"
      assert kanban =~ "https://jira.example.com/browse/"
    end
  end

  describe "empty project" do
    test "views work on empty project" do
      tapestry = Tapestry.new("Empty")

      assert Tapestry.to_kanban(tapestry) =~ "kanban"
      assert Tapestry.to_timeline(tapestry) =~ "gantt"
      assert Tapestry.to_graph(tapestry) =~ "graph TD"
    end

    test "analysis works on empty project" do
      tapestry = Tapestry.new("Empty")

      assert Tapestry.ready(tapestry) == []
      assert Tapestry.blocked(tapestry) == []
      assert Tapestry.orphans(tapestry) == []
      assert Tapestry.bottlenecks(tapestry) == []
      assert Tapestry.validate(tapestry) == []
      assert {:ok, [], total_estimate: 0} = Tapestry.critical_path(tapestry)
    end
  end
end
