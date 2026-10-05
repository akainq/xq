// An HTTP server on std/http: a process per connection; the request counter is a separate process.
// Usage:  xq run examples/http_server.xq -- 8080   then: curl http://127.0.0.1:8080/hello
// HTTPS:  xq run examples/http_server.xq -- 8443 cert.pem key.pem
//
// `http.serve(server, handler)` is enough when the handler does not need messages.
// Here a connection asks the counter and waits for the reply in its mailbox, so the
// connection loop is written with `http.readRequest` / `http.respond`.
import * as http from "std/http";
import * as net from "std/net";

type StatsMsg = { type: "hit"; path: string } | { type: "get"; replyTo: Pid<Map<string, int>> };

function stats(this: Process<StatsMsg>, hits: Map<string, int>): void {
  receive {
    { type: "hit", path } => stats(hits.set(path, (hits.get(path) ?? 0) + 1)),
    { type: "get", replyTo } => {
      replyTo.send(hits);
      stats(hits);
    },
  }
}

function report(this: Process<Map<string, int>>, statsPid: Pid<StatsMsg>): http.Response {
  statsPid.send({ type: "get", replyTo: self() });
  return receive {
    hits =>
      http.text(
        hits
          .entries()
          .map(([p, n]) => `${p}: ${n}`)
          .join("\n") +
          "\n",
      ),
    after 1000 => http.text("stats timeout\n", 503),
  };
}

// Keep-alive: the process answers requests of its connection until the client closes it.
function connection(this: Process<Map<string, int>>, s: net.Socket, statsPid: Pid<StatsMsg>): void {
  const req = http.readRequest(s);
  if (req === null) {
    net.close(s);
    return;
  }
  statsPid.send({ type: "hit", path: req.path });
  const res =
    req.path === "/stats"
      ? report(statsPid)
      : http.text(`Hello from XQ! You requested ${req.path}\n`);
  if (http.respond(s, req, res) && req.keepAlive) {
    connection(s, statsPid);
  } else {
    net.close(s);
  }
}

function acceptLoop(server: http.Server, statsPid: Pid<StatsMsg>): void {
  const a = net.accept(server.listener);
  if (a.ok) {
    const s = a.value;
    net.handOver(s, spawn(connection, s, statsPid));
  }
  acceptLoop(server, statsPid);
}

function main(): void {
  const a = args();
  const port = a.length > 0 ? parseInt(a[0]) ?? 8080 : 8080;
  const s =
    a.length > 2
      ? http.listen({ host: "127.0.0.1", port, cert: a[1], key: a[2] })
      : http.listen({ host: "127.0.0.1", port });
  if (!s.ok) {
    console.log("cannot listen:", s.error);
    return;
  }
  console.log(`listening on ${s.value.tls ? "https" : "http"}://127.0.0.1:${s.value.port}/`);
  acceptLoop(s.value, spawn(stats, new Map()));
}
