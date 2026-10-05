// Text (std/gpu): the Inter font from a file, lines in Russian and English, sizes from 8 to 48 pixels,
// alignment at a point, and a frame counter and the pointer position: labels that change every frame.
// The frame is rebuilt on every `frame` event; Esc closes the window. Run from the repository root:
// `xq run examples/text.xq`.
import * as gpu from "std/gpu";
import * as fs from "std/fs";

type State = { width: float; height: float; x: float; y: float; fps: float; t: float; frames: int };

const INK: gpu.Color = { r: 0.92, g: 0.94, b: 0.98, a: 1.0 };
const DIM: gpu.Color = { r: 0.55, g: 0.6, b: 0.7, a: 1.0 };
const ACCENT: gpu.Color = { r: 1.0, g: 0.75, b: 0.3, a: 1.0 };

const POEM = "Мороз и солнце; день чудесный!\nЕщё ты дремлешь, друг прелестный —\nПора, красавица, проснись.";

function scene(f: gpu.Font, s: State): gpu.Frame {
  const sizes = [8, 10, 12, 14, 18, 24, 32, 48];
  const sized = sizes.map((px, i) => {
    const y = 150.0 + toFloat(sizes.slice(0, i).reduce((a, b) => a + b, 0)) * 1.3;
    return gpu.text(f, `${px} px · The quick brown fox · съешь ещё булок`, 24.0, y, toFloat(px), INK);
  });
  const mid = s.width / 2.0;
  const fps = gpu.text(f, `${s.fps.toFixed(1)} fps`, s.width - 16.0, 12.0, 16.0, ACCENT, "right");
  const pointer = gpu.text(f, `pointer: ${s.x.toFixed(0)}, ${s.y.toFixed(0)}`, 24.0, s.height - 32.0, 14.0, DIM);
  const head = gpu.text(f, "XQ · std/gpu · text", 24.0, 16.0, 28.0, INK);
  const poem = gpu.text(f, POEM, mid, 64.0, 18.0, DIM, "center");
  // The point that the lines of the poem are aligned on.
  const line = gpu.rects(Float32Array.of(mid - 0.5, 60.0, 1.0, 70.0, 1.0, 0.75, 0.3, 0.35));
  return gpu.frame([gpu.pass(gpu.screen, gpu.rgb(0.07, 0.08, 0.11), [line, head, fps, poem, ...sized, pointer])]);
}

function loop(this: Process<gpu.Event>, f: gpu.Font, w: gpu.Window, s: State): void {
  receive {
    { type: "frame", dt } => {
      gpu.present(w, scene(f, s));
      // The frame rate is recomputed every half second.
      const t = s.t + dt;
      if (t >= 0.5) {
        loop(f, w, { ...s, fps: toFloat(s.frames + 1) / t, t: 0.0, frames: 0 });
      } else {
        loop(f, w, { ...s, t, frames: s.frames + 1 });
      }
    },
    { type: "resize", width, height } => loop(f, w, { ...s, width: toFloat(width), height: toFloat(height) }),
    { type: "pointer", x, y } => loop(f, w, { ...s, x, y }),
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
  const w = gpu.window({ title: "XQ: text", width: 1200, height: 720 });
  if (!w.ok) panic(w.error);
  loop(font.value, w.value, { width: 1200.0, height: 720.0, x: 0.0, y: 0.0, fps: 0.0, t: 0.0, frames: 0 });
}
