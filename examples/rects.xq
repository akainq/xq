// 10,000 rectangles in a window (std/gpu). A frame is a value: the process builds it anew when the window
// is ready for the next one (the `frame` event, like requestAnimationFrame) and passes it to `gpu.present`.
// Once a second it prints how many frames were shown and how long it took to build one. Esc closes the window.
import * as gpu from "std/gpu";

/** A 100 × 100 grid of rectangles over a `width` × `height` window, swaying with the time `t`:
 * 8 numbers per rectangle — x, y, width, height, r, g, b, a. */
function fill(a: Float32Array, i: int, t: float, width: float, height: float): Float32Array {
  if (i === 10000) return a;
  const col = toFloat(i % 100);
  const row = toFloat(i / 100);
  const cw = width / 100.0;
  const ch = height / 100.0;
  const k = 8 * i;
  return fill(
    a
      .with(k, col * cw + 0.2 * cw * Math.sin(t + toFloat(i) * 0.1))
      .with(k + 1, row * ch)
      .with(k + 2, 0.8 * cw)
      .with(k + 3, 0.8 * ch)
      .with(k + 4, col / 100.0)
      .with(k + 5, row / 100.0)
      .with(k + 6, 0.6)
      .with(k + 7, 1.0),
    i + 1,
    t,
    width,
    height,
  );
}

function frames(
  this: Process<gpu.Event>,
  w: gpu.Window,
  rects: Float32Array,
  width: float,
  height: float,
  shown: int,
  since: float,
  work: float,
): void {
  receive {
    { type: "frame", n } => {
      const start = performance.now();
      const next = fill(rects, 0, toFloat(n) / 60.0, width, height);
      gpu.present(w, gpu.frame([gpu.pass(gpu.screen, gpu.rgb(0.1, 0.1, 0.12), [gpu.rects(next)])]));
      const now = performance.now();
      const spent = work + (now - start);
      if (now - since < 1000.0) {
        frames(w, next, width, height, shown + 1, since, spent);
      } else {
        const k = toFloat(shown + 1);
        console.log(`${shown + 1} frames a second, ${(spent / k).toFixed(3)} ms to build and present one`);
        frames(w, next, width, height, 0, now, 0.0);
      }
    },
    { type: "resize", width: rw, height: rh } => frames(w, rects, toFloat(rw), toFloat(rh), shown, since, work),
    { type: "key", key: "Escape", down: true } => gpu.close(w),
    { type: "closed" } => {},
    _ => frames(w, rects, width, height, shown, since, work),
  }
}

function main(this: Process<gpu.Event>): void {
  const w = gpu.window({ title: "XQ: 10 000 rects", width: 1200, height: 700 });
  if (!w.ok) panic(w.error);
  frames(w.value, new Float32Array(80000), 1200.0, 700.0, 0, performance.now(), 0.0);
}
