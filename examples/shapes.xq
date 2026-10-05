type Shape =
  | { kind: "circle"; r: float }
  | { kind: "rect"; w: float; h: float }
  | { kind: "square"; side: float };

function area(s: Shape): float {
  return match (s) {
    { kind: "circle", r } => Math.PI * r * r,
    { kind: "rect", w, h } => w * h,
    { kind: "square", side } => side * side,
  };
}

function describe(s: Shape): string {
  if (s.kind === "circle") {
    return `circle of radius ${s.r}`;
  }
  return `shape ${s.kind} with area ${area(s).toFixed(2)}`;
}

type Point = { x: int; y: int };

function main(): void {
  const shapes: Shape[] = [
    { kind: "circle", r: 1.5 },
    { kind: "rect", w: 2.0, h: 3.0 },
    { kind: "square", side: 4.0 },
  ];
  for (const s of shapes) {
    console.log(describe(s));
  }
  const total = shapes.map((s) => area(s)).reduce((a, b) => a + b, 0.0);
  console.log("total area:", total.toFixed(3));

  const p: Point = { x: 1, y: 2 };
  const q = { ...p, y: 10 }; // An immutable update: p stays as it was.
  console.log(p, q, p === { x: 1, y: 2 }); // Structural equality: records are compared by value.

  const xs = [5, 3, 8, 1];
  const sorted = xs.toSorted();
  console.log(
    xs,
    sorted,
    xs.with(0, 42),
    [...xs, 99].filter((x) => x > 4),
  );
  const [first, ...rest] = sorted;
  console.log(first, rest, rest.length);

  const add = (a: int) => (b: int) => a + b; // Closures: the inner function captures a.
  const add10 = add(10);
  console.log(add10(5), [1, 2, 3].map(add10));

  const maybe: int | null = xs.length > 3 ? 7 : null;
  console.log(maybe ?? 0, maybe !== null ? maybe * 2 : -1);
}
