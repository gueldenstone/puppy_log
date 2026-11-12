defmodule PuppyLogWeb.WeightChart do
  @moduledoc """
  Server-rendered SVG weight curve. X axis in weeks of life when the birth
  date is known, otherwise in calendar days since the first weighing.
  """

  use Phoenix.Component

  alias PuppyLog.Puppy.Weight

  @width 330
  @height 140
  @left 26
  @right 10
  @top 12
  @bottom 112

  attr :entries, :list, required: true, doc: "weight entries in any order"
  attr :birth_date, :any, default: nil

  def chart(assigns) do
    assigns = assign(assigns, :model, build(assigns.entries, assigns.birth_date))

    ~H"""
    <p :if={@model == :too_few} class="py-6 text-center text-[14px] text-muted">
      Ab zwei Einträgen erscheint hier die Kurve.
    </p>
    <svg
      :if={@model != :too_few}
      viewBox={"0 0 #{width()} #{height()}"}
      class="block w-full"
      role="img"
      aria-label={@model.label}
    >
      <g stroke="#DDE3DE" stroke-dasharray="3 3">
        <line :for={t <- @model.y_ticks} x1={left()} x2={width() - right()} y1={t.y} y2={t.y} />
      </g>
      <g font-size="11" fill="#55645D">
        <text :for={t <- @model.y_ticks} x="0" y={t.y + 4}>{t.label}</text>
      </g>
      <polyline
        points={Enum.map_join(@model.points, " ", &"#{&1.x},#{&1.y}")}
        fill="none"
        stroke="#0E6B52"
        stroke-width="3"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <circle :for={p <- Enum.drop(@model.points, -1)} cx={p.x} cy={p.y} r="3.5" fill="#0E6B52" />
      <circle
        cx={List.last(@model.points).x}
        cy={List.last(@model.points).y}
        r="5"
        fill="#0E6B52"
        stroke="#fff"
        stroke-width="2"
      />
      <g font-size="11" fill="#55645D" text-anchor="middle">
        <text
          :for={t <- @model.x_ticks}
          x={t.x}
          y={height() - 6}
          font-weight={t.last && "600"}
          fill={t.last && "#14201B"}
          text-anchor={t.last && t.x > width() - 30 && "end"}
        >
          {t.label}
        </text>
      </g>
    </svg>
    """
  end

  defp width, do: @width
  defp height, do: @height
  defp left, do: @left
  defp right, do: @right

  @doc false
  def build(entries, birth_date) when length(entries) < 2, do: build_few(entries, birth_date)

  def build(entries, birth_date) do
    entries = Enum.sort_by(entries, & &1.measured_on, Date)
    first_date = hd(entries).measured_on
    unit = if birth_date, do: :weeks, else: :days

    raw =
      Enum.map(entries, fn e ->
        x =
          case unit do
            :weeks -> Date.diff(e.measured_on, birth_date) / 7
            :days -> Date.diff(e.measured_on, first_date)
          end

        {x, e.weight_grams}
      end)

    {xs, ys} = Enum.unzip(raw)
    {x_min, x_max} = widen(Enum.min(xs), Enum.max(xs), 1)
    {y_min, y_max, y_step} = y_scale(Enum.min(ys), Enum.max(ys))

    sx = fn x -> round1(@left + (x - x_min) / (x_max - x_min) * (@width - @left - @right)) end
    sy = fn y -> round1(@bottom - (y - y_min) / (y_max - y_min) * (@bottom - @top)) end

    points = Enum.map(raw, fn {x, y} -> %{x: sx.(x), y: sy.(y)} end)

    y_ticks =
      y_min
      |> Stream.iterate(&(&1 + y_step))
      |> Enum.take_while(&(&1 <= y_max))
      |> Enum.map(&%{y: sy.(&1), label: Weight.to_kg_string(&1)})

    %{
      points: points,
      y_ticks: y_ticks,
      x_ticks: x_ticks(raw, sx, unit, first_date),
      label: label(entries, unit, birth_date)
    }
  end

  defp build_few(_entries, _birth_date), do: :too_few

  defp widen(min, max, _pad) when max > min, do: {min, max}
  defp widen(min, _max, pad), do: {min - pad, min + pad}

  # nice y range in grams with 2-4 grid lines
  defp y_scale(min, max) do
    span = max(max - min, 200)
    step = Enum.find([100, 200, 250, 500, 1000, 2000, 5000, 10_000], 10_000, &(span / &1 <= 3))
    lo = div(min, step) * step
    hi = (div(max - 1, step) + 1) * step
    hi = if hi == lo, do: lo + step, else: hi
    {lo, hi, step}
  end

  defp x_ticks(raw, sx, :weeks, _first_date) do
    weeks = raw |> Enum.map(fn {x, _} -> trunc(x) end) |> Enum.uniq()
    last = List.last(weeks)
    every = max(div(length(weeks) + 5, 6), 1)

    weeks
    |> Enum.with_index()
    |> Enum.filter(fn {w, i} -> rem(i, every) == 0 or w == last end)
    |> Enum.map(fn {w, _} ->
      %{x: sx.(w + 0.0), label: if(w == last, do: "#{w} W.", else: "#{w}"), last: w == last}
    end)
    |> clamp_x(raw, sx)
  end

  defp x_ticks(raw, sx, :days, first_date) do
    {first_x, _} = hd(raw)
    {last_x, _} = List.last(raw)

    [{first_x, false}, {last_x, true}]
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.map(fn {x, last} ->
      date = Date.add(first_date, x)
      %{x: sx.(x), label: "#{date.day}.#{date.month}.", last: last}
    end)
  end

  # Weeks are truncated, so a label could sit left of the plot; keep it inside.
  defp clamp_x(ticks, _raw, _sx), do: Enum.map(ticks, &%{&1 | x: max(&1.x, @left)})

  defp label(entries, unit, _birth_date) do
    first = hd(entries)
    last = List.last(entries)

    from_to =
      "von #{Weight.to_kg_string(first.weight_grams)} kg auf #{Weight.to_kg_string(last.weight_grams)} kg"

    case unit do
      :weeks -> "Gewichtskurve nach Lebenswochen: #{from_to}"
      :days -> "Gewichtskurve: #{from_to}"
    end
  end

  defp round1(value), do: Float.round(value * 1.0, 1)
end
