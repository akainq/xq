function fib(n: int): int {
  if (n < 2) return n;
  return fib(n - 1) + fib(n - 2);
}

// Tail recursion instead of loops: the stack does not grow.
function sumTo(n: int, acc: int): int {
  if (n === 0) return acc;
  return sumTo(n - 1, acc + n);
}

function main(): void {
  console.log("fib(30) =", fib(30));
  console.log("sumTo(10_000_000) =", sumTo(10_000_000, 0));
}
