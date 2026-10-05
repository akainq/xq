// Many short-lived processes: their stacks are reused from a pool.
function collect(this: Process<int>, n: int, acc: int): int {
  if (n === 0) return acc;
  receive {
    x => collect(n - 1, acc + x),
  }
}

function main(this: Process<int>): void {
  const n = 200_000;
  const me = self();
  const t0 = now();
  for (const i of range(0, n)) {
    spawn(() => me.send(i));
  }
  const total = collect(n, 0);
  console.log(`${n} processes, sum ${total}, ${now() - t0} ms`);
}
