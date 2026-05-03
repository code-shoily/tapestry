defmodule Tapestry.View.Timeline do
  @moduledoc """
  Timeline / Gantt chart projections of a Tapestry project.

  Generates Mermaid Gantt syntax, which is the most practical text-based
  format for Gantt charts. GraphViz DOT is designed for node-link graphs,
  not bar-chart timelines — Mermaid has native Gantt support.
  """

  alias Tapestry
  alias Tapestry.Helpers
  alias Tapestry.Query

  @default_date_format "YYYY-MM-DD"

  @doc """
  Generates a Mermaid Gantt chart string.

  ## Options

  - `:title` — Chart title (defaults to project name)
  - `:milestone` — Only include tasks under this milestone
  - `:section_by` — `:milestone` or `:assignee` to group tasks into sections
  - `:start_date` — Base date for synthetic scheduling (defaults to today)

  ## Examples

      iex> tapestry = Tapestry.new("Launch")
      ...> |> Tapestry.add_task(:design, title: "Design", status: :done, estimate_hours: 16)
      ...> |> Tapestry.add_task(:impl, title: "Implement", status: :backlog, estimate_hours: 24)
      ...> |> Tapestry.depends_on(:impl, :design)
      iex> gantt = Tapestry.View.Timeline.to_timeline(tapestry, start_date: ~D[2026-05-01])
      iex> gantt =~ "gantt"
      true
      iex> gantt =~ "Launch"
      true
      iex> gantt =~ "Design"
      true
  """
  @spec to_timeline(Tapestry.t(), keyword()) :: String.t()
  def to_timeline(%Tapestry{} = tapestry, opts \\ []) do
    title = Keyword.get(opts, :title, tapestry.name || "Project Timeline")
    section_by = Keyword.get(opts, :section_by, :milestone)
    base_date = Keyword.get(opts, :start_date, Date.utc_today())

    tasks =
      case Keyword.get(opts, :milestone) do
        nil -> Query.tasks(tapestry)
        m_id -> Query.tasks(tapestry) |> filter_by_milestone(tapestry, m_id)
      end

    if tasks == [] do
      "gantt\n    title #{Helpers.escape(title)}\n"
    else
      # Compute start dates and durations for all tasks
      schedule = compute_schedule(tapestry, tasks, base_date)

      header = [
        "gantt",
        "    title #{Helpers.escape(title)}",
        "    dateFormat #{@default_date_format}"
      ]

      sections = group_into_sections(tasks, tapestry, section_by)

      section_lines =
        Enum.flat_map(sections, fn {section_name, section_tasks} ->
          task_lines =
            Enum.map(section_tasks, fn {id, data} ->
              render_task(id, data, schedule)
            end)

          ["    section #{Helpers.escape(section_name)}" | task_lines]
        end)

      (header ++ section_lines)
      |> Enum.join("\n")
      |> Kernel.<>("\n")
    end
  end

  # --- Rendering ---

  defp render_task(id, data, schedule) do
    name = Helpers.escape(data[:title] || inspect(id))
    {start_date, duration_days} = Map.fetch!(schedule, id)
    tags = mermaid_tags(data)
    task_id = Helpers.sanitize_id(id)

    start_str = Date.to_iso8601(start_date)
    duration_str = if duration_days == 1, do: "1d", else: "#{duration_days}d"

    meta =
      if tags == [] do
        "#{task_id}, #{start_str}, #{duration_str}"
      else
        "#{Enum.join(tags, ", ")}, #{task_id}, #{start_str}, #{duration_str}"
      end

    "        #{name} : #{meta}"
  end

  defp mermaid_tags(data) do
    []
    |> then(fn acc -> if data[:status] == :done, do: ["done" | acc], else: acc end)
    |> then(fn acc -> if data[:status] == :in_progress, do: ["active" | acc], else: acc end)
    |> then(fn acc -> if data[:priority] == :critical, do: ["crit" | acc], else: acc end)
    |> Enum.reverse()
  end

  # --- Scheduling ---

  defp compute_schedule(tapestry, tasks, base_date) do
    task_ids = Enum.map(tasks, fn {id, _} -> id end) |> MapSet.new()

    # Build dependency order among the selected tasks
    dag = Helpers.build_restricted_dag(tapestry, task_ids)

    {:ok, sorted} =
      case Yog.Traversal.Sort.topological_sort(dag) do
        {:ok, s} -> {:ok, s}
        # If cyclic or empty, just use original order
        _ -> {:ok, Enum.map(tasks, fn {id, _} -> id end)}
      end

    # Compute start dates
    Enum.reduce(sorted, %{}, fn id, acc ->
      data = tapestry.graph.nodes[id]

      {start, duration} =
        case {data[:start_date], data[:due_date], data[:estimate_hours]} do
          {start_date, due_date, _} when not is_nil(start_date) and not is_nil(due_date) ->
            duration = max(Date.diff(due_date, start_date) + 1, 1)
            {start_date, duration}

          {start_date, nil, hrs} when not is_nil(start_date) ->
            duration = estimate_to_days(hrs)
            {start_date, duration}

          {nil, due_date, hrs} when not is_nil(due_date) ->
            duration = estimate_to_days(hrs)
            start = Date.add(due_date, -duration)
            {start, duration}

          {nil, nil, hrs} ->
            duration = estimate_to_days(hrs)
            start = synthetic_start(dag, id, acc, base_date)
            {start, duration}
        end

      Map.put(acc, id, {start, duration})
    end)
  end

  defp synthetic_start(dag, id, schedule, base_date) do
    preds = Helpers.predecessors(dag, id)

    if preds == [] do
      base_date
    else
      # Start after the latest predecessor ends
      preds
      |> Enum.map(fn p ->
        case Map.fetch(schedule, p) do
          {:ok, {p_start, p_dur}} -> Date.add(p_start, p_dur)
          :error -> base_date
        end
      end)
      |> Enum.max_by(&Date.to_gregorian_days/1)
    end
  end

  defp estimate_to_days(nil), do: 1
  defp estimate_to_days(hrs) when hrs <= 0, do: 1
  defp estimate_to_days(hrs), do: max(trunc(Float.ceil(hrs / 8)), 1)

  # --- Sectioning ---

  defp group_into_sections(tasks, tapestry, :milestone) do
    tasks
    |> Enum.group_by(fn {id, _} ->
      case Query.parent(tapestry, id) do
        nil -> "Backlog"
        m_id -> tapestry.graph.nodes[m_id][:title] || inspect(m_id)
      end
    end)
    |> Enum.to_list()
  end

  defp group_into_sections(tasks, tapestry, :assignee) do
    tasks
    |> Enum.group_by(fn {id, _} ->
      case Query.assignee(tapestry, id) do
        nil -> "Unassigned"
        u_id -> tapestry.graph.nodes[u_id][:name] || inspect(u_id)
      end
    end)
    |> Enum.to_list()
  end

  defp group_into_sections(tasks, _, _) do
    [{"Tasks", tasks}]
  end

  defp filter_by_milestone(tasks, tapestry, m_id) do
    ms_children = Query.children(tapestry, m_id) |> MapSet.new()
    Enum.filter(tasks, fn {id, _} -> id in ms_children end)
  end
end
