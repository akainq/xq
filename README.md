# XQ

**One program. Many machines. Native code.**

XQ is a compiled language for distributed systems. Lightweight isolated processes talk through typed messages, and a
pid works the same whether its process is next door or on another machine: `send`, `call`, `link` and `monitor`
cross the network as they are. When a machine goes away, links and monitors say so with a message, and supervisors
start the work again elsewhere. Programs compile to native code through LLVM — no virtual machine, no garbage
collector.

Website and guide: **https://akainq.github.io/xq/**

```ts
import * as node from "std/node";

type Job = { type: "square"; n: int; reply: Pid<int> };

// Exported, so that any node of the cluster can start it.
export function worker(this: Process<Job>): void {
  receive {
    { type: "square", n, reply } => {
      reply.send(n * n);
      worker();
    },
  }
}

// On 10.0.0.2 the same program starts as node "b".
function main(this: Process<int>): void {
  node.start({ name: "a", host: "10.0.0.1" });
  node.connect("b@10.0.0.2:4370");
  // A process on the other machine. Its pid is like any
  // other: send, call, link and monitor take it as it is.
  const w = node.spawn("b", worker);
  if (!w.ok) return;
  w.value.send({ type: "square", n: 12, reply: self() });
  receive {
    n => console.log("b says:", n),
  }
}
```

```
$ XQ_NODE_SECRET=s3cret xq run cluster.xq
b says: 144
```

- **A pid is a pid.** `send`, `call`, `link`, `monitor`, `pid.kill` and broadcasts take a pid of a process of another
  node; `node.spawn` starts an exported function there, `node.find` finds a process by its name.
- **Failures are messages.** A node that crashes, hangs or drops off the network fires every link and monitor through
  it: `Exit` and `Down` with reason `noconnection`, and a supervisor can start its children again on a node that is
  still up.
- **Typed on the wire.** The compiler writes a codec for every message type, and the receiving node checks each
  message against the mailbox type of its receiver.
- **A cluster by itself.** Process groups across the nodes, all the nodes connected to each other, connections
  encrypted with Noise and no certificates, long messages in pieces that do not hold up the others.
- **Fast.** Between two nodes of one machine (Linux), a call takes 10 µs (Erlang/OTP 29: 45), one sender sends 2.6
  million messages a second (0.68 million), and a broadcast through a group on three nodes makes 7.4 million
  deliveries a second (1.9 million).
- **The rest of a language.** Immutable values, processes with heaps of their own, reference counting without a
  garbage collector, supervisors, HTTP, PostgreSQL and Redis clients, C calls, graphics on Vulkan.

## Install

Download the archive for your platform from [Releases](https://github.com/akainq/xq/releases), unpack it and add the
folder to `PATH`. It holds `xq` and the runtime libraries next to it.

| Platform | Archive |
|---|---|
| Windows x86-64 | `xq-<version>-x86_64-windows.zip` |
| Linux x86-64 | `xq-<version>-x86_64-linux.tar.gz` |
| Linux ARM64 | `xq-<version>-aarch64-linux.tar.gz` |
| macOS, Apple Silicon | `xq-<version>-aarch64-macos.tar.gz` |
| macOS, Intel | `xq-<version>-x86_64-macos.tar.gz` |

On Windows and Linux nothing else is needed: the archive carries the LLVM XQ compiles with (clang and lld) and what
programs link with. On macOS XQ compiles programs with clang 15 or later:

- **Windows:** nothing to install; Windows 10 or later.
- **Linux:** nothing to install; programs need glibc 2.39 or later (Ubuntu 24.04, Debian 13).
- **Other platforms:** the archives for Windows and Linux build programs for all three platforms:
  `xq build app.xq --target x86_64-linux` (or `x86_64-windows`, `aarch64-linux`).
- **macOS:** `xcode-select --install`. A browser marks downloaded files as quarantined: download with `curl -LO`, or
  run `xattr -dr com.apple.quarantine xq-*` before unpacking.

```
xq --version
xq run examples/hello.xq
```

## Learn

- [The guide to the language](https://akainq.github.io/xq/guide.html)
- [Projects and tests](https://akainq.github.io/xq/projects.html): `xq.toml`, `xq build`, `xq test`
- [Packages](https://akainq.github.io/xq/projects.html#packages): `xq add`, versions and `xq.lock`; the registry is
  [akainq.github.io/xq-packages](https://akainq.github.io/xq-packages/)
- [Examples](examples): processes, supervisors, chats on three nodes (rooms as processes and as process groups),
  an HTTP server, SQLite through C, windows and graphics

## This repository

Releases, the website (`docs/`, served by GitHub Pages) and examples. The compiler is developed in a separate
repository; questions and bug reports are welcome in [Issues](https://github.com/akainq/xq/issues).

## License

MIT OR Apache-2.0, at your option: [LICENSE-MIT](LICENSE-MIT), [LICENSE-APACHE](LICENSE-APACHE).
