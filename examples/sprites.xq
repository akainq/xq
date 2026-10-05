// 100,000 sprites (std/gpu). The image is decoded from PNG and uploaded to the GPU in the background, and the
// frame (100,000 sprites in one `Float32Array`) is rebuilt on every `frame` event: the sprites fly around,
// bounce off the edges of the window and spin. Once a second it prints how many frames were shown and how
// much time the process spends per frame. The image is the first argument or examples/sprite.png; Esc
// closes the window.
import * as gpu from "std/gpu";
import * as fs from "std/fs";

const N = 100000;
const SIZE = 16.0;

/** Sprites: 13 numbers each — x, y, width, height, u0, v0, u1, v1, angle, r, g, b, a; velocities: 2 each. */
type World = { sprites: Float32Array; vel: Float32Array };

/** A number from 0 to 1, derived from `i`. */
function rnd(i: int): float {
  const a = (i * 7919 + 104729) % 67108859;
  const b = (a * a + 12345) % 67108859;
  return toFloat((b * b + 67890) % 67108859) / 67108859.0;
}

/** The initial number `f` of sprite `i`: somewhere in the window, at a random angle, in a light color. */
function initial(i: int, f: int, width: float, height: float): float {
  if (f === 0) return rnd(5 * i) * (width - SIZE);
  if (f === 1) return rnd(5 * i + 1) * (height - SIZE);
  if (f === 2 || f === 3) return SIZE;
  if (f === 4 || f === 5) return 0.0;
  if (f === 6 || f === 7) return 1.0;
  if (f === 8) return rnd(5 * i + 2) * 2.0 * Math.PI;
  if (f === 12) return 1.0;
  return 0.4 + 0.6 * rnd(5 * i + f - 6);
}

function world(width: float, height: float): World {
  return {
    sprites: Float32Array.from(range(0, 13 * N).map((j) => initial(j / 13, j % 13, width, height))),
    vel: Float32Array.from(range(0, 2 * N).map((j) => (rnd(3 * j + 11) * 2.0 - 1.0) * 200.0)),
  };
}

/** The sprites from the `i`-th one on, moved by `dt` seconds. The arrays are unique, so they change in place;
 * the steps do not depend on each other, so the loop is split across cores. */
function step(w: World, i: int, dt: float, width: float, height: float): World {
  if (i === w.vel.length / 2) return w;
  const k = 13 * i;
  const x = w.sprites[k] + w.vel[2 * i] * dt;
  const y = w.sprites[k + 1] + w.vel[2 * i + 1] * dt;
  const vx = x < 0.0 ? Math.abs(w.vel[2 * i]) : x > width - SIZE ? -Math.abs(w.vel[2 * i]) : w.vel[2 * i];
  const vy = y < 0.0 ? Math.abs(w.vel[2 * i + 1]) : y > height - SIZE ? -Math.abs(w.vel[2 * i + 1]) : w.vel[2 * i + 1];
  return step(
    {
      sprites: w.sprites.with(k, x).with(k + 1, y).with(k + 8, w.sprites[k + 8] + 2.0 * dt),
      vel: w.vel.with(2 * i, vx).with(2 * i + 1, vy),
    },
    i + 1,
    dt,
    width,
    height,
  );
}

function frames(
  this: Process<gpu.Event>,
  win: gpu.Window,
  tex: gpu.Texture,
  w: World,
  width: float,
  height: float,
  shown: int,
  since: float,
  work: float,
): void {
  receive {
    { type: "frame", dt } => {
      const start = performance.now();
      const next = step(w, 0, Math.min(dt, 0.05), width, height);
      gpu.present(win, gpu.frame([gpu.pass(gpu.screen, gpu.rgb(0.1, 0.1, 0.12), [gpu.sprites(tex, next.sprites)])]));
      const now = performance.now();
      const spent = work + (now - start);
      if (now - since < 1000.0) {
        frames(win, tex, next, width, height, shown + 1, since, spent);
      } else {
        const k = toFloat(shown + 1);
        console.log(`${N} sprites: ${shown + 1} frames a second, ${(spent / k).toFixed(2)} ms to move, build and present one`);
        frames(win, tex, next, width, height, 0, now, 0.0);
      }
    },
    { type: "resize", width: rw, height: rh } => frames(win, tex, w, toFloat(rw), toFloat(rh), shown, since, work),
    { type: "key", key: "Escape", down: true } => gpu.close(win),
    { type: "closed" } => {},
    _ => frames(win, tex, w, width, height, shown, since, work),
  }
}

function main(this: Process<gpu.Event>): void {
  const a = args();
  const path = a.length > 0 ? a[0] : "examples/sprite.png";
  const data = fs.readBytes(path);
  if (!data.ok) panic(`${path}: ${data.error}`);
  const img = gpu.decodeImage(data.value);
  if (!img.ok) panic(`${path}: ${img.error}`);
  const win = gpu.window({ title: "XQ: 100 000 sprites", width: 1280, height: 720 });
  if (!win.ok) panic(win.error);
  const tex = gpu.texture(img.value);
  frames(win.value, tex, world(1280.0, 720.0), 1280.0, 720.0, 0, performance.now(), 0.0);
}
