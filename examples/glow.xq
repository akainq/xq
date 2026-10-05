// Custom shaders (std/gpu): 3,000 particles fly in circles; the frame is drawn into a texture and reaches the
// screen with a glow: the bright spots at half size, blurred horizontally and vertically, added to the frame.
// Each step is a custom material in WGSL (`gpu.material`), a pass into its own texture. Space turns the glow
// on and off, Esc closes the window. Run from the repository root: `xq run examples/glow.xq`.
import * as gpu from "std/gpu";
import * as fs from "std/fs";

const N = 3000;
const WIDTH = 1200;
const HEIGHT = 720;

// A pass over the whole target: texture coordinates run from 0 to 1.
const WHOLE = `
struct Out {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs(@builtin(vertex_index) i: u32) -> Out {
    var o: Out;
    let c = gpu_corner(i);
    o.pos = gpu_position(c * gpu_size());
    o.uv = c;
    return o;
}
`;

// Bright spots: whatever is brighter than the threshold, amplified.
const BRIGHT =
  WHOLE +
  `
@fragment
fn fs(i: Out) -> @location(0) vec4<f32> {
    let c = gpu_sample(0u, i.uv).rgb;
    return vec4<f32>(max(c - vec3<f32>(0.35), vec3<f32>(0.0)) * 2.0, 1.0);
}
`;

// A 9-texel Gaussian blur in the direction given by the instance.
const BLUR = `
struct Out {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) @interpolate(flat) step: vec2<f32>,
};

@vertex
fn vs(@builtin(vertex_index) i: u32, @location(0) direction: vec2<f32>) -> Out {
    var o: Out;
    let c = gpu_corner(i);
    o.pos = gpu_position(c * gpu_size());
    o.uv = c;
    o.step = direction / gpu_texture_size(0u);
    return o;
}

@fragment
fn fs(i: Out) -> @location(0) vec4<f32> {
    let w = array<f32, 5>(0.227, 0.194, 0.121, 0.054, 0.016);
    var sum = gpu_sample(0u, i.uv).rgb * w[0];
    for (var k = 1; k < 5; k++) {
        let d = i.step * f32(k) * 2.0;
        sum += (gpu_sample(0u, i.uv + d).rgb + gpu_sample(0u, i.uv - d).rgb) * w[k];
    }
    return vec4<f32>(sum, 1.0);
}
`;

// The glow is added on top of the frame.
const GLOW =
  WHOLE +
  `
@fragment
fn fs(i: Out) -> @location(0) vec4<f32> {
    return vec4<f32>(gpu_sample(0u, i.uv).rgb * 1.5, 1.0);
}
`;

type Look = {
  sprite: gpu.Texture;
  font: gpu.Font;
  bright: gpu.Material;
  blur: gpu.Material;
  glow: gpu.Material;
  scene: gpu.Texture;
  a: gpu.Texture;
  b: gpu.Texture;
};

type State = { t: float; on: bool };

/** A number from 0 to 1, derived from `i`. */
function rnd(i: int): float {
  const a = (i * 7919 + 104729) % 67108859;
  const b = (a * a + 12345) % 67108859;
  return toFloat((b * b + 67890) % 67108859) / 67108859.0;
}

/** The particles at time `t`: circling the center, each at its own radius and speed. */
function particles(t: float): Float32Array {
  return Float32Array.from(
    range(0, 13 * N).map((j) => {
      const i = j / 13;
      const k = j % 13;
      const r = 60.0 + 300.0 * rnd(i);
      const a = t * (0.2 + 0.8 * rnd(i + 7)) + 6.28318 * rnd(i + 13);
      const size = 4.0 + 10.0 * rnd(i + 21);
      if (k === 0) return 600.0 + r * Math.cos(a) - size / 2.0;
      if (k === 1) return 360.0 + r * Math.sin(a) * 0.8 - size / 2.0;
      if (k === 2 || k === 3) return size;
      if (k === 4 || k === 5 || k === 8) return 0.0;
      if (k === 6 || k === 7 || k === 12) return 1.0;
      // Colors: one channel is full, the others are random.
      return k - 9 === i % 3 ? 1.0 : 0.3 + 0.5 * rnd(i * 3 + k);
    }),
  );
}

function scene(l: Look, s: State): gpu.Frame {
  const none = new Float32Array(0);
  const label = gpu.text(l.font, `glow: ${s.on ? "on" : "off"} (space)`, 16.0, 12.0, 16.0, gpu.rgb(0.8, 0.85, 0.95));
  const draw = gpu.pass(l.scene, gpu.rgb(0.02, 0.02, 0.05), [gpu.sprites(l.sprite, particles(s.t))]);
  const show = (items: gpu.Item[]) => gpu.pass(gpu.screen, null, [gpu.image(l.scene, 0.0, 0.0, toFloat(WIDTH), toFloat(HEIGHT)), ...items, label]);
  if (!s.on) return gpu.frame([draw, show([])]);
  return gpu.frame([
    draw,
    gpu.pass(l.a, null, [gpu.draw(l.bright, none, [l.scene])]),
    gpu.pass(l.b, null, [gpu.draw(l.blur, Float32Array.of(1.0, 0.0), [l.a])]),
    gpu.pass(l.a, null, [gpu.draw(l.blur, Float32Array.of(0.0, 1.0), [l.b])]),
    show([gpu.draw(l.glow, none, [l.a])]),
  ]);
}

function loop(this: Process<gpu.Event>, l: Look, w: gpu.Window, s: State): void {
  receive {
    { type: "frame", dt } => {
      gpu.present(w, scene(l, s));
      loop(l, w, { ...s, t: s.t + dt });
    },
    { type: "key", key: " ", down: true } => loop(l, w, { ...s, on: !s.on }),
    { type: "key", key: "Escape", down: true } => gpu.close(w),
    { type: "closed" } => {},
    _ => loop(l, w, s),
  }
}

function compiled(src: string, blend: gpu.Blend): gpu.Material {
  const m = gpu.material(src, { blend });
  if (!m.ok) panic(m.error);
  return m.value;
}

function main(this: Process<gpu.Event>): void {
  const png = fs.readBytes("examples/sprite.png");
  if (!png.ok) panic(`examples/sprite.png: ${png.error}`);
  const img = gpu.decodeImage(png.value);
  if (!img.ok) panic(img.error);
  const file = fs.readBytes("examples/fonts/Inter-Regular.ttf");
  if (!file.ok) panic(`examples/fonts/Inter-Regular.ttf: ${file.error}`);
  const font = gpu.font(file.value);
  if (!font.ok) panic(font.error);
  const w = gpu.window({ title: "XQ: glow", width: WIDTH, height: HEIGHT });
  if (!w.ok) panic(w.error);
  const l: Look = {
    sprite: gpu.texture(img.value),
    font: font.value,
    bright: compiled(BRIGHT, "replace"),
    blur: compiled(BLUR, "replace"),
    glow: compiled(GLOW, "add"),
    scene: gpu.texture({ width: WIDTH, height: HEIGHT }),
    a: gpu.texture({ width: WIDTH / 2, height: HEIGHT / 2 }),
    b: gpu.texture({ width: WIDTH / 2, height: HEIGHT / 2 }),
  };
  loop(l, w.value, { t: 0.0, on: true });
}
