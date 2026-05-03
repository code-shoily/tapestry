defmodule Tapestry.ViewableTest do
  use ExUnit.Case

  doctest Tapestry.Visibility
  doctest Tapestry.View.KanbanSpec
  doctest Tapestry.View.TimelineSpec
  doctest Tapestry.View.GraphSpec
  doctest Tapestry.View.AnalysisSpec

  alias Tapestry.Visibility
  alias Tapestry.Viewable

  # ---- Visibility struct tests ----

  describe "Visibility" do
    test "all/0 returns unfiltered visibility" do
      vis = Visibility.all()
      assert vis.node_types == []
      assert vis.edge_types == []
      assert vis.fields == []
      assert vis.exclude_fields == []
    end

    test "includes_node_type?/2 allows all when node_types is empty" do
      vis = %Visibility{}
      assert Visibility.includes_node_type?(vis, :task)
      assert Visibility.includes_node_type?(vis, :anything)
    end

    test "includes_node_type?/2 filters when node_types is set" do
      vis = %Visibility{node_types: [:task, :milestone]}
      assert Visibility.includes_node_type?(vis, :task)
      assert Visibility.includes_node_type?(vis, :milestone)
      refute Visibility.includes_node_type?(vis, :user)
    end

    test "includes_edge_type?/2 allows all when edge_types is empty" do
      vis = %Visibility{}
      assert Visibility.includes_edge_type?(vis, :depends_on)
    end

    test "includes_edge_type?/2 filters when edge_types is set" do
      vis = %Visibility{edge_types: [:depends_on, :blocks]}
      assert Visibility.includes_edge_type?(vis, :depends_on)
      refute Visibility.includes_edge_type?(vis, :assigned_to)
    end

    test "includes_field?/2 always includes :type" do
      vis = %Visibility{fields: [:title]}
      assert Visibility.includes_field?(vis, :type)
    end

    test "includes_field?/2 with explicit fields" do
      vis = %Visibility{fields: [:title, :status]}
      assert Visibility.includes_field?(vis, :title)
      assert Visibility.includes_field?(vis, :status)
      refute Visibility.includes_field?(vis, :body)
    end

    test "includes_field?/2 with exclude_fields" do
      vis = %Visibility{exclude_fields: [:body, :email]}
      assert Visibility.includes_field?(vis, :title)
      refute Visibility.includes_field?(vis, :body)
      refute Visibility.includes_field?(vis, :email)
    end

    test "filter_fields/2 with no restrictions returns data unchanged" do
      vis = %Visibility{}
      data = %{type: :task, title: "A", body: "long text"}
      assert Visibility.filter_fields(vis, data) == data
    end

    test "filter_fields/2 with explicit fields keeps only those + :type" do
      vis = %Visibility{fields: [:title, :status]}
      data = %{type: :task, title: "A", status: :done, body: "long", priority: :high}
      filtered = Visibility.filter_fields(vis, data)

      assert Map.has_key?(filtered, :type)
      assert Map.has_key?(filtered, :title)
      assert Map.has_key?(filtered, :status)
      refute Map.has_key?(filtered, :body)
      refute Map.has_key?(filtered, :priority)
    end

    test "filter_fields/2 with exclude_fields removes those" do
      vis = %Visibility{exclude_fields: [:body]}
      data = %{type: :task, title: "A", body: "long text"}
      filtered = Visibility.filter_fields(vis, data)

      assert Map.has_key?(filtered, :title)
      refute Map.has_key?(filtered, :body)
    end
  end

  # ---- Viewable protocol tests ----

  defp sample_loom do
    Tapestry.new("Test Project")
    |> Tapestry.add_milestone(:v1, title: "V1 Launch")
    |> Tapestry.add_task(:design, title: "Design", status: :done, estimate_hours: 8)
    |> Tapestry.add_task(:impl, title: "Implement", status: :in_progress, estimate_hours: 16)
    |> Tapestry.add_task(:test, title: "Test", status: :backlog, estimate_hours: 4)
    |> Tapestry.add_user(:alice, name: "Alice")
    |> Tapestry.add_label(:frontend)
    |> Tapestry.contains(:v1, :design)
    |> Tapestry.contains(:v1, :impl)
    |> Tapestry.contains(:v1, :test)
    |> Tapestry.depends_on(:impl, :design)
    |> Tapestry.depends_on(:test, :impl)
    |> Tapestry.assign(:design, :alice)
    |> Tapestry.tag(:design, :frontend)
  end

  describe "KanbanSpec" do
    test "visibility returns correct spec" do
      spec = %Tapestry.View.KanbanSpec{milestone: :v1}
      vis = Viewable.visibility(spec)

      assert vis.root == :v1
      assert vis.depth == 1
      assert :task in vis.node_types
      assert :user in vis.node_types
      assert :assigned_to in vis.edge_types
    end

    test "visibility without milestone has no root" do
      spec = %Tapestry.View.KanbanSpec{}
      vis = Viewable.visibility(spec)

      assert vis.root == nil
      assert vis.depth == nil
    end

    test "render produces kanban output" do
      loom = sample_loom()
      spec = %Tapestry.View.KanbanSpec{}

      result = Viewable.render(spec, loom)
      assert is_binary(result)
      assert result =~ "kanban"
      assert result =~ "Design"
    end

    test "render with milestone filter" do
      loom = sample_loom()
      spec = %Tapestry.View.KanbanSpec{milestone: :v1}

      result = Viewable.render(spec, loom)
      assert result =~ "Design"
    end

    test "render_view/2 works through facade" do
      loom = sample_loom()
      spec = %Tapestry.View.KanbanSpec{}

      result = Tapestry.render_view(loom, spec)
      assert is_binary(result)
      assert result =~ "kanban"
    end
  end

  describe "TimelineSpec" do
    test "visibility returns scheduling fields" do
      spec = %Tapestry.View.TimelineSpec{}
      vis = Viewable.visibility(spec)

      assert :estimate_hours in vis.fields
      assert :start_date in vis.fields
      assert :due_date in vis.fields
      assert :depends_on in vis.edge_types
    end

    test "render produces gantt output" do
      loom = sample_loom()
      spec = %Tapestry.View.TimelineSpec{start_date: ~D[2026-05-01]}

      result = Viewable.render(spec, loom)
      assert is_binary(result)
      assert result =~ "gantt"
      assert result =~ "Design"
    end

    test "render with section_by assignee" do
      loom = sample_loom()
      spec = %Tapestry.View.TimelineSpec{section_by: :assignee, start_date: ~D[2026-05-01]}

      result = Viewable.render(spec, loom)
      assert result =~ "section Alice"
    end
  end

  describe "GraphSpec" do
    test "visibility includes edge types based on show_ flags" do
      spec = %Tapestry.View.GraphSpec{show_assignments: true, show_labels: true}
      vis = Viewable.visibility(spec)

      assert :assigned_to in vis.edge_types
      assert :tagged_with in vis.edge_types
      assert :user in vis.node_types
      assert :label in vis.node_types
    end

    test "visibility excludes edge types when show_ flags are false" do
      spec = %Tapestry.View.GraphSpec{}
      vis = Viewable.visibility(spec)

      refute :assigned_to in vis.edge_types
      refute :tagged_with in vis.edge_types
      assert :depends_on in vis.edge_types
      assert :contains in vis.edge_types
    end

    test "render produces flowchart output" do
      loom = sample_loom()
      spec = %Tapestry.View.GraphSpec{direction: :lr}

      result = Viewable.render(spec, loom)
      assert is_binary(result)
      assert result =~ "graph LR"
    end
  end

  describe "AnalysisSpec" do
    test "visibility is minimal for analysis" do
      spec = %Tapestry.View.AnalysisSpec{operation: :critical_path}
      vis = Viewable.visibility(spec)

      assert :status in vis.fields
      assert :estimate_hours in vis.fields
      refute :title in vis.fields
    end

    test "render dispatches ready" do
      loom = sample_loom()
      spec = %Tapestry.View.AnalysisSpec{operation: :ready}

      result = Viewable.render(spec, loom)
      assert is_list(result)
    end

    test "render dispatches critical_path" do
      loom = sample_loom()
      spec = %Tapestry.View.AnalysisSpec{operation: :critical_path}

      assert {:ok, path, total_estimate: _total} = Viewable.render(spec, loom)
      assert is_list(path)
    end

    test "render dispatches validate" do
      loom = sample_loom()
      spec = %Tapestry.View.AnalysisSpec{operation: :validate}

      result = Viewable.render(spec, loom)
      assert is_list(result)
      # impl is in_progress but assigned — alice is assigned to design not impl
      assert {:warning, :unassigned_in_progress, :impl} in result
    end

    test "render dispatches bottlenecks" do
      loom = sample_loom()
      spec = %Tapestry.View.AnalysisSpec{operation: :bottlenecks}

      result = Viewable.render(spec, loom)
      assert is_list(result)
      {top_id, _count} = hd(result)
      assert top_id == :design
    end
  end

  describe "transform is identity for all specs" do
    test "all specs return loom unchanged from transform" do
      loom = sample_loom()

      specs = [
        %Tapestry.View.KanbanSpec{},
        %Tapestry.View.TimelineSpec{},
        %Tapestry.View.GraphSpec{},
        %Tapestry.View.AnalysisSpec{}
      ]

      for spec <- specs do
        assert Viewable.transform(spec, loom) == loom
      end
    end
  end
end
