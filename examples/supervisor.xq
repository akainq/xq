// "Let it crash": the worker crashes, and the observer learns of it through monitor.
type WorkerMsg = { type: "work"; n: int };
type SupMsg = Down | Exit | { type: "done"; result: int };

function worker(this: Process<WorkerMsg>, parent: Pid<SupMsg>): void {
  receive {
    { type: "work", n } => {
      parent.send({ type: "done", result: 100 / n }); // When n == 0, the process crashes.
      worker(parent);
    },
  }
}

function collect(this: Process<SupMsg>, left: int): void {
  if (left === 0) return;
  receive {
    { type: "done", result } => {
      console.log("result:", result);
      collect(left - 1);
    },
    { type: "DOWN", pid, reason } => {
      console.log(`worker ${pid} crashed: ${reason}`);
      collect(left - 1);
    },
    { type: "EXIT", pid, reason } => {
      console.log(`linked ${pid} exited: ${reason}`);
      collect(left - 1);
    },
    after 2000 => console.log("timeout"),
  }
}

function main(this: Process<SupMsg>): void {
  const w = spawn(worker, self());
  monitor(w);
  w.send({ type: "work", n: 5 });
  w.send({ type: "work", n: 0 });
  w.send({ type: "work", n: 2 }); // This one is never handled: the worker is already dead.
  collect(2);

  trapExit(true);
  spawnLink(() => panic("boom"));
  collect(1);
  console.log("supervisor is alive");
}
