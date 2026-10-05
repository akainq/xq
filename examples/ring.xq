// A ring of N processes: the token goes around the ring M times.
type Token = { hops: int };

function node(this: Process<Token | Pid<Token>>, next: Pid<Token> | null): void {
  receive {
    nxt: Pid<Token> => node(nxt),
    { hops } => {
      if (next === null) return;
      next.send({ hops: hops + 1 });
      node(next);
    },
  }
}

function last(this: Process<Token>, main: Pid<int>, target: int): void {
  receive {
    { hops } => {
      if (hops >= target) {
        main.send(hops);
      } else {
        main.send(-hops);
      }
      last(main, target);
    },
  }
}

function main(this: Process<int>): void {
  const n = 100_000;
  const t0 = now();
  const tail = spawn(last, self(), n);
  // Build the chain: node_i -> node_{i+1} -> ... -> tail.
  const head = buildChain(n - 1, tail);
  const t1 = now();
  console.log(`spawned ${n} processes in ${t1 - t0} ms`);
  head.send({ hops: 1 });
  receive {
    hops => console.log(`token passed ${hops} hops in ${now() - t1} ms`),
  }
}

function buildChain(k: int, next: Pid<Token>): Pid<Token> {
  if (k === 0) return next;
  const p = spawn<Token | Pid<Token>>(() => node(next));
  return buildChain(k - 1, p);
}
