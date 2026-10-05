// A live chart (std/gpu): a new value arrives every frame, and a polyline of the last 600 values
// runs from right to left inside a panel with rounded corners and clipping, with a grid and scale
// labels beneath it and a dot for the latest value on top of it; the pointer shows the value under
// it. The frame is rebuilt on every `frame` event; Esc closes the window. Run from the repository
// root: `xq run examples/chart.xq`.
import * as gpu from "std/gpu";
import * as fs from "std/fs";

const N = 600;
const PANEL: gpu.Color = { r: 0.1, g: 0.11, b: 0.15, a: 1.0 };
const FRAME: gpu.Color = { r: 0.3, g: 0.34, b: 0.45, a: 1.0 };
const GRID: gpu.Color = { r: 0.25, g: 0.28, b: 0.36, a: 1.0 };
const INK: gpu.Color = { r: 0.85, g: 0.88, b: 0.95, a: 1.0 };
const LINE: gpu.Color = { r: 0.3, g: 0.8, b: 1.0, a: 1.0 };
const MARK: gpu.Color = { r: 1.0, g: 0.75, b: 0.3, a: 1.0 };

type State = { width: float; height: float; px: float; values: float[]; t: float };

/** The next value: two waves and a little noise. */
function sample(t: float): float {
  return 50.0 + 30.0 * Math.sin(t * 1.3) + 12.0 * Math.sin(t * 4.1 + 1.0) + 4.0 * Math.sin(t * 23.0);
}

function scene(f: gpu.Font, s: State): gpu.Frame {
  // The plot area.
  const x0 = 80.0;
  const y0 = 70.0;
  const w = s.width - 120.0;
  const h = s.height - 140.0;
  const y = (v: float): float => y0 + h - v / 100.0 * h;
  const points = Float32Array.from(range(0, 2 * N).map((j) => (j % 2 === 0 ? x0 + toFloat(j / 2) * w / toFloat(N - 1) : y(s.values[j / 2]))));
  // Grid lines and labels every 20 units.
  const ticks = range(0, 6).map((k) => toFloat(k * 20));
  const grid = ticks.map((v) => gpu.line(x0, y(v), x0 + w, y(v), 1.0, GRID));
  const labels = ticks.map((v) => gpu.text(f, `${v.toFixed(0)}`, x0 - 12.0, y(v) - 8.0, 13.0, INK, "right"));
  const last = s.values[N - 1];
  const hover = s.px >= x0 && s.px <= x0 + w;
  const i = hover ? toInt((s.px - x0) / w * toFloat(N - 1) + 0.5) : N - 1;
  const v = s.values[i];
  const cursor = hover ? [gpu.line(s.px, y0, s.px, y0 + h, 1.0, FRAME), gpu.text(f, v.toFixed(1), s.px + 6.0, y(v) - 22.0, 14.0, MARK)] : [];
  return gpu.frame([
    gpu.pass(gpu.screen, gpu.rgb(0.05, 0.05, 0.08), [
      gpu.roundRect(x0 - 70.0, y0 - 50.0, w + 100.0, h + 90.0, 12.0, PANEL, 1.5, FRAME),
      gpu.text(f, "Sensor · last 600 values", x0, y0 - 38.0, 18.0, INK),
      gpu.text(f, `now ${last.toFixed(1)}`, x0 + w, y0 - 38.0, 18.0, MARK, "right"),
      ...grid,
      ...labels,
      // The polyline is drawn only inside the plot area.
      gpu.clip(x0, y0, w, h, [gpu.polyline(points, 2.0, LINE)]),
      gpu.circle(x0 + w, y(last), 4.0, MARK),
      ...cursor,
      gpu.circle(x0 + toFloat(i) * w / toFloat(N - 1), y(v), 3.0, PANEL, 1.5, MARK),
    ]),
  ]);
}

function loop(this: Process<gpu.Event>, f: gpu.Font, w: gpu.Window, s: State): void {
  receive {
    { type: "frame", dt } => {
      gpu.present(w, scene(f, s));
      const t = s.t + dt;
      loop(f, w, { ...s, t, values: [...s.values.slice(1), sample(t)] });
    },
    { type: "resize", width, height } => loop(f, w, { ...s, width: toFloat(width), height: toFloat(height) }),
    { type: "pointer", x } => loop(f, w, { ...s, px: x }),
    { type: "key", key: "Escape", down: true } => gpu.close(w),
    { type: "closed" } => {},
    _ => loop(f, w, s),
  }
}

function main(this: Process<gpu.Event>): void {
  const file = fs.readBytes("examples/fonts/Inter-Regular.ttf");
  if (!file.ok) panic(`examples/fonts/Inter-Regular.ttf: ${file.error}`);
  const font = gpu.font(file.value);
  if (!font.ok) panic(font.error);
  const w = gpu.window({ title: "XQ: chart", width: 1100, height: 600 });
  if (!w.ok) panic(w.error);
  const values = range(0, N).map((k) => sample(toFloat(k - N) / 60.0));
  loop(font.value, w.value, { width: 1100.0, height: 600.0, px: -1.0, values, t: 0.0 });
}
