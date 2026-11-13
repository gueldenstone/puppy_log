defmodule PuppyLogWeb.HistoryCharts do
  @moduledoc """
  Server-rendered charts of „Verlauf“ (docs/design/Verlauf.dc.html): the
  adherence bars per day or week and the outside/inside split bars.
  """

  use Phoenix.Component

  import PuppyLogWeb.UI, only: [pl_icon: 1]

  alias PuppyLogWeb.Format

  # bar area of each column's SVG (scaled to the column width)
  @bar_height 60

  @doc """
  One bar per bucket of `PuppyLog.Daily.Stats.compute/2`. Today's bucket is
  highlighted, buckets without counted routines (nothing yet, still open) are
  dashed. Daily buckets link to their day view.
  """
  attr :buckets, :list, required: true

  def adherence_bars(assigns) do
    count = length(assigns.buckets)

    assigns =
      assign(assigns,
        count: count,
        gap: gap(count),
        values?: count <= 14,
        every: max(div(count + 6, 7), 1),
        bar_height: @bar_height
      )

    ~H"""
    <div
      class={["mt-2.5 grid items-end", @gap]}
      style={"grid-template-columns: repeat(#{@count}, minmax(0, 1fr))"}
    >
      <.bar_column
        :for={{bucket, index} <- Enum.with_index(@buckets)}
        bucket={bucket}
        values?={@values?}
        label?={bucket.today? or rem(@count - 1 - index, @every) == 0}
        bar_height={@bar_height}
      />
    </div>
    """
  end

  attr :bucket, :map, required: true
  attr :values?, :boolean, required: true
  attr :label?, :boolean, required: true
  attr :bar_height, :integer, required: true

  defp bar_column(%{bucket: %{first: same, last: same}} = assigns) do
    ~H"""
    <.link
      navigate={"/history/#{Date.to_iso8601(@bucket.first)}"}
      aria-label={"#{Format.short_date(@bucket.first)} ansehen"}
      class="group flex min-w-0 flex-col items-center gap-0.5 rounded-md transition active:scale-95"
    >
      <.bar_body bucket={@bucket} values?={@values?} label?={@label?} bar_height={@bar_height} />
    </.link>
    """
  end

  defp bar_column(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col items-center gap-0.5">
      <.bar_body bucket={@bucket} values?={@values?} label?={@label?} bar_height={@bar_height} />
    </div>
    """
  end

  attr :bucket, :map, required: true
  attr :values?, :boolean, required: true
  attr :label?, :boolean, required: true
  attr :bar_height, :integer, required: true

  defp bar_body(assigns) do
    height =
      case assigns.bucket.rate do
        nil -> 4
        rate -> max(round(rate / 100 * assigns.bar_height), 2)
      end

    assigns = assign(assigns, height: height)

    ~H"""
    <span
      :if={@values?}
      class={[
        "h-4 text-[11px] leading-4 tabular-nums",
        if(@bucket.today?, do: "font-semibold text-ink", else: "text-muted")
      ]}
    >
      {@bucket.rate}
    </span>
    <svg
      viewBox={"0 0 20 #{@bar_height}"}
      preserveAspectRatio="none"
      class="block h-[60px] w-full transition group-hover:opacity-80"
      role="img"
      aria-label={bar_label(@bucket)}
    >
      <rect
        :if={@bucket.rate}
        x="0"
        y={@bar_height - @height}
        width="20"
        height={@height}
        rx="3"
        fill={if @bucket.today?, do: "#8CCBB4", else: "#0E6B52"}
        stroke={@bucket.today? && "#0E6B52"}
        stroke-width={@bucket.today? && "2"}
        vector-effect="non-scaling-stroke"
      />
      <rect
        :if={!@bucket.rate}
        x="0.5"
        y={@bar_height - @height}
        width="19"
        height={@height - 0.5}
        rx="2"
        fill="none"
        stroke={if @bucket.today?, do: "#0E6B52", else: "#A9B5AE"}
        stroke-dasharray="3 2"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    <span class={[
      "h-4 max-w-full overflow-visible whitespace-nowrap text-[12px] leading-4",
      if(@bucket.today?, do: "font-semibold text-ink", else: "text-muted")
    ]}>
      {if @label?, do: @bucket.label}
    </span>
    """
  end

  defp gap(count) when count <= 7, do: "gap-2"
  defp gap(count) when count <= 14, do: "gap-1"
  defp gap(_count), do: "gap-0.5"

  defp bar_label(%{rate: nil} = bucket),
    do: "#{bucket_name(bucket)}: noch keine Routinen ausgewertet"

  defp bar_label(bucket),
    do:
      "#{bucket_name(bucket)}: #{bucket.rate} Prozent eingehalten, #{bucket.kept} von #{bucket.counted}"

  defp bucket_name(%{first: same, last: same}), do: Format.short_date(same)

  defp bucket_name(bucket),
    do: "#{bucket.label} (#{Format.date_range(bucket.first, bucket.last)})"

  @doc """
  Outside/inside split of pee or poo: a title with „21 draußen · 2 drinnen“
  and a bar (accent outside, red inside).
  """
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true, doc: "text color class of the title"
  attr :counts, :map, required: true, doc: "%{outside: n, inside: n}"

  def split_bar(assigns) do
    total = assigns.counts.outside + assigns.counts.inside
    percent = if total > 0, do: round(assigns.counts.outside * 100 / total)
    assigns = assign(assigns, total: total, percent: percent)

    ~H"""
    <div>
      <div class="flex items-center justify-between gap-2 text-[14px] leading-5">
        <span class={["flex items-center gap-1.5 font-semibold", @color]}>
          <.pl_icon name={@icon} class="size-4" />{@title}
        </span>
        <span class="tabular-nums">
          {@counts.outside} draußen · {@counts.inside} drinnen
        </span>
      </div>
      <svg
        viewBox="0 0 100 10"
        preserveAspectRatio="none"
        class="mt-1 block h-2.5 w-full overflow-hidden rounded-[5px]"
        role="img"
        aria-label={split_label(@title, @percent)}
      >
        <rect :if={!@percent} width="100" height="10" fill="#E4EAE6" />
        <rect :if={@percent} width={@percent} height="10" fill="#0E6B52" />
        <rect
          :if={@percent && @percent < 100}
          x={@percent}
          width={100 - @percent}
          height="10"
          fill="#F0C6C0"
        />
        <line
          :if={@percent && @percent < 100}
          x1={@percent}
          x2={@percent}
          y1="0"
          y2="10"
          stroke="#A32A1C"
          stroke-width="2"
          vector-effect="non-scaling-stroke"
        />
      </svg>
    </div>
    """
  end

  defp split_label(title, nil), do: "#{title}: noch nichts eingetragen"
  defp split_label(title, percent), do: "#{title}: #{percent} Prozent draußen"
end
