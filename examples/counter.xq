// A counter process: its state lives in the arguments of a tail-recursive call.
type CounterMsg = { type: "inc"; by: int } | { type: "get"; replyTo: Pid<int> } | { type: "stop" };

function counter(this: Process<CounterMsg>, value: int): void {
  receive {
    { type: "inc", by } => counter(value + by),
    { type: "get", replyTo } => {
      replyTo.send(value);
      counter(value);
    },
    { type: "stop" } => console.log(`counter: stopped at ${value}`),
  }
}

function main(this: Process<int>): void {
  const c = spawn(counter, 0);
  for (const i of range(1, 101)) {
    c.send({ type: "inc", by: i });
  }
  c.send({ type: "get", replyTo: self() });
  receive {
    total => console.log("sum of 1..100 =", total),
    after 1000 => console.log("timeout!"),
  }
  c.send({ type: "stop" });
  sleep(50);
}
