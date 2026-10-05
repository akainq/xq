type Ping = { tag: "ping"; from: Pid<Pong>; n: int };
type Pong = { tag: "pong"; n: int };

function ponger(this: Process<Ping | { tag: "quit" }>): void {
  receive {
    { tag: "ping", from, n } => {
      from.send({ tag: "pong", n });
      ponger();
    },
    { tag: "quit" } => console.log("ponger: bye"),
  }
}

function pinger(this: Process<Pong>, peer: Pid<Ping>, left: int): void {
  if (left === 0) return;
  peer.send({ tag: "ping", from: self(), n: left });
  receive {
    { tag: "pong", n } => {
      if (n % 25000 === 0) console.log("pong", n);
      pinger(peer, left - 1);
    },
  }
}

function main(this: Process<Pong>): void {
  const p = spawn(ponger);
  const t0 = now();
  pinger(p, 100_000);
  const dt = now() - t0;
  console.log(`100000 round-trips in ${dt} ms`);
  p.send({ tag: "quit" });
  sleep(20);
}
