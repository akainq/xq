// Rooms of a chat as process groups, on three nodes: a user joins a room by joining its group
// (`node.join`) and says a line by sending it to the members of the group (`node.members`),
// wherever they are — no process keeps the room. When a node is gone, its users are out of the
// rooms on the other nodes. This program is node a, and it runs itself as nodes b and c, which
// connect to a and, through what a tells them, to each other; on three machines it would be
// started three times, with `host` and the secret in `node.start` and the address of node a in
// `node.connect`.
//
// The members of a group converge: a node learns of a join on another as soon as the frame
// comes. A client that must know that all of them hear a line waits until each user sees them
// all (`count`), as the program does below, which plays the clients of the users: it tells them
// what to do and prints what they hear.
//
//   xq run examples/node_rooms.xq
import * as node from "std/node";
import * as exec from "std/exec";
import * as os from "std/os";

/** A line said in a room, to its members. */
type Line = { type: "said"; room: string; who: string; text: string };

/** What the client of a user tells it, as a socket would bring it, and what it tells the client. */
type Cmd =
  | { type: "hello"; client: Pid<Client> }
  | { type: "join"; room: string }
  | { type: "leave"; room: string }
  | { type: "say"; room: string; text: string }
  | { type: "count"; room: string; reply: Pid<int> };
type Client = { type: "heard"; by: string; room: string; who: string; text: string };

type User = Cmd | Line;

export type Main = node.NodeEvent | Client;

/** The group of room `name`. */
function group(name: string): string {
  return `room:${name}`;
}

/** A user waits for its client. */
function waiting(this: Process<User>, me: string): void {
  receive {
    { type: "hello", client } => user(me, client),
  }
}

function user(this: Process<User>, me: string, client: Pid<Client>): void {
  receive {
    { type: "join", room } => {
      node.join(group(room), self());
      user(me, client);
    },
    { type: "leave", room } => {
      node.leave(group(room), self());
      user(me, client);
    },
    { type: "say", room, text } => {
      // One frame to each node with members, whatever their number there.
      send(node.members<Line>(group(room)), { type: "said", room, who: me, text });
      user(me, client);
    },
    { type: "said", room, who, text } => {
      client.send({ type: "heard", by: me, room, who, text });
      user(me, client);
    },
    { type: "count", room, reply } => {
      reply.send(node.members<Line>(group(room)).length);
      user(me, client);
    },
    { type: "hello" } => user(me, client),
  }
}

/** Nodes b and c: a user, until node a is gone. */
function child(this: Process<Main>, name: string, who: string, a: string): void {
  const me = node.start({ name, port: 0, secret: "rooms" });
  if (!me.ok) panic(me.error);
  spawn({ name: who }, waiting, who);
  node.watch();
  const c = node.connect(a);
  if (!c.ok) panic(c.error);
  untilGone("a");
}

function untilGone(this: Process<Main>, n: string): void {
  receive {
    { type: "nodedown", node } => {
      if (node !== n) untilGone(n);
    },
    other => untilGone(n),
  }
}

/** Until this node is connected with `n` others. */
function waitUp(this: Process<Main>, n: int): void {
  if (node.nodes().length >= n) return;
  receive {
    { type: "nodeup" } => waitUp(n),
    after 20000 => panic("the nodes did not come"),
  }
}

function userOn(on: string, name: string): Pid<User> {
  const f = node.find<User>(on, name);
  if (!f.ok || f.value === null) panic(`no user ${name} on node ${on}`);
  return f.value;
}

/** Until each of `users` sees `n` members in room `room`. */
function settled(users: Pid<User>[], room: string, n: int, tries: int): void {
  const counts = users.map((u) => u.call((reply) => ({ type: "count", room, reply }), 5000));
  if (counts.every((c) => c.ok && c.value === n)) return;
  if (tries === 0) panic(`room ${room} does not settle: ${counts}`);
  sleep(10);
  settled(users, room, n, tries - 1);
}

/** Prints the line `n` users heard, and who heard it. */
function heard(this: Process<Main>, n: int, line: string, users: string[]): void {
  if (n === 0) {
    console.log(`${line} -> ${users.sort().join(", ")}`);
    return;
  }
  receive {
    { type: "heard", by, room, who, text } =>
      heard(n - 1, `${room}: ${who}: ${text}`, [...users, by]),
    after 10000 => panic(`not heard by all: ${line}`),
  }
}

/** Until node `n` is gone. */
function down(this: Process<Main>, n: string): void {
  receive {
    { type: "nodedown", node } => {
      if (node === n) console.log(`node ${n} is gone`);
      else down(n);
    },
    after 20000 => panic(`node ${n} did not go`),
  }
}

/** Exported: a test runs the example as it is. */
export function main(this: Process<Main>): void {
  const a = args();
  if (a.length === 3) return child(a[0], a[1], a[2]);
  const me = node.start({ name: "a", port: 0, secret: "rooms" });
  if (!me.ok) panic(me.error);
  node.watch();
  const ann = spawn({ name: "ann" }, waiting, "ann");
  const b = exec.start(
    os.executable(),
    ["b", "bob", me.value],
    { stdout: "inherit", stderr: "inherit" },
  );
  const c = exec.start(
    os.executable(),
    ["c", "eve", me.value],
    { stdout: "inherit", stderr: "inherit" },
  );
  if (!b.ok || !c.ok) panic("cannot run nodes b and c");
  waitUp(2);
  console.log("nodes:", node.nodes());
  const bob = userOn("b", "bob");
  const eve = userOn("c", "eve");
  for (const u of [ann, bob, eve]) u.send({ type: "hello", client: self() });
  for (const u of [ann, bob, eve]) u.send({ type: "join", room: "general" });
  for (const u of [bob, eve]) u.send({ type: "join", room: "random" });
  settled([ann, bob, eve], "general", 3, 500);
  settled([bob, eve], "random", 2, 500);
  ann.send({ type: "say", room: "general", text: "hi" });
  heard(3, "", []);
  eve.send({ type: "say", room: "random", text: "anyone?" });
  heard(2, "", []);
  // Node c goes with eve: she is out of both rooms.
  exec.kill(c.value);
  down("c");
  settled([ann, bob], "general", 2, 500);
  ann.send({ type: "join", room: "random" });
  settled([ann, bob], "random", 2, 500);
  ann.send({ type: "say", room: "random", text: "back" });
  heard(2, "", []);
  bob.send({ type: "leave", room: "general" });
  settled([ann, bob], "general", 1, 500);
  ann.send({ type: "say", room: "general", text: "still here" });
  heard(1, "", []);
  console.log("nodes:", node.nodes());
}
