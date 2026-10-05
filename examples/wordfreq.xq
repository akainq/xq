// Counts word frequencies in standard input: std/io + Map + in-place updates.
// Usage: xq run examples/wordfreq.xq < some.txt
import { readAll } from "std/io";

function count(words: string[], i: int, freq: Map<string, int>): Map<string, int> {
  if (i === words.length) return freq;
  const w = words[i];
  // Only tokens containing letters count as words.
  if (w.toUpperCase() === w.toLowerCase()) return count(words, i + 1, freq);
  return count(words, i + 1, freq.set(w, (freq.get(w) ?? 0) + 1));
}

function main(): void {
  const text = readAll().toLowerCase();
  const words = text.split("\n").join(" ").split(" ");
  const freq = count(words, 0, new Map());
  const top = freq
    .entries()
    .toSorted((a, b) => (b[1] - a[1] !== 0 ? b[1] - a[1] : a[0] < b[0] ? -1 : 1))
    .slice(0, 5);
  console.log(`${freq.size} distinct words`);
  for (const [w, n] of top) {
    console.log(`${n.toString().padStart(6)}  ${w}`);
  }
}
