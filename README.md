# XQ

**Immutable values, isolated processes, native code.**

XQ is a compiled language for concurrent programs. Lightweight processes, each with a heap of its own, talk through
typed messages; a crash stays inside its process, and supervisors restart it. Programs compile to native code through
LLVM, with no garbage collector and no virtual machine.

Website and guide: **https://akainq.github.io/xq/**

```ts
type Msg =
  | { type: "inc"; by: int }
  | { type: "get"; replyTo: Pid<int> };

// A process is a function; its state lives in the arguments of a tail call.
function counter(this: Process<Msg>, value: int): void {
  receive {
    { type: "inc", by } => counter(value + by),
    { type: "get", replyTo } => {
      replyTo.send(value);
      counter(value);
    },
  }
}

function main(this: Process<int>): void {
  const c = spawn(counter, 0);
  c.send({ type: "inc", by: 42 });
  c.send({ type: "get", replyTo: self() });
  receive {
    n => console.log("value:", n),
  }
}
```

```
$ xq run counter.xq
value: 42
```

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

XQ compiles programs with clang 15 or later:

- **Windows:** [LLVM](https://github.com/llvm/llvm-project/releases) (clang) and the C++ build tools of
  [Visual Studio](https://visualstudio.microsoft.com/visual-cpp-build-tools/).
- **Linux:** `sudo apt install clang`; glibc 2.39 or later (Ubuntu 24.04, Debian 13).
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
- [Examples](examples): processes, supervisors, an HTTP server, SQLite through C, windows and graphics

## This repository

Releases, the website (`docs/`, served by GitHub Pages) and examples. The compiler is developed in a separate
repository; questions and bug reports are welcome in [Issues](https://github.com/akainq/xq/issues).

## License

MIT OR Apache-2.0, at your option: [LICENSE-MIT](LICENSE-MIT), [LICENSE-APACHE](LICENSE-APACHE).
