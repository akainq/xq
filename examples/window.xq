// A window and its events (std/gpu): prints everything that arrives until the window is closed.
// A program that imports std/gpu is built with the runtime that has graphics; the others are built
// without it.
import * as gpu from "std/gpu";

function events(this: Process<gpu.Event>, w: gpu.Window): void {
  receive {
    { type: "closed" } => console.log("closed"),
    { type: "key", key: "Escape", down: true } => console.log("escape"),
    e => {
      console.log(e);
      events(w);
    },
  }
}

function main(this: Process<gpu.Event>): void {
  const w = gpu.window({ title: "XQ: events", width: 640, height: 400 });
  if (!w.ok) panic(w.error);
  events(w.value);
}
