// A chat on three nodes: rooms are processes on any of them, users are on any of them, and the
// lines of a room go to its members wherever they are. This program is node a, and it runs itself
// as nodes b and c; on three machines it would be started three times, with `host` and the
// secret in `node.start` and the address of node a in `node.connect`.
//
// Node a keeps the directory of rooms; a room starts on the next node in turn (`node.spawn`, which
// starts the exported function `room` there). Rooms watch their members and forget those that are
// gone, users watch their rooms. When a node is gone, its rooms start again on another node: the
// directory starts such a room when it gets its `Down`, or when a member asks where the room is
// now, whichever comes first, and the members join it there.
//
// The program plays the clients of the users: it tells them what to do and prints what they hear.
//
//   xq run examples/node_chat.xq
import * as node from "std/node";
import * as exec from "std/exec";
import * as os from "std/os";

/** A line said in a room, to its members. */
type Line = { type: "said"; room: string; who: string; text: string };

/** A room: `join` answers with the node of the room once the user is a member. */
type Room =
  | { type: "join"; user: string; to: Pid<Line>; reply: Pid<string> }
  | { type: "say"; user: string; text: string }
  | Down;

/** The directory of rooms, on node a: where room `name` is; `gone` is where it was, if the
 * member that asks saw it go. */
type Dir = { type: "where"; name: string; gone: Pid<Room> | null; reply: Pid<Pid<Room>> } | Down;

/** What the client of a user tells it, as a socket would bring it, and what it tells the client. */
type Cmd =
  | { type: "hello"; client: Pid<Client> }
  | { type: "join"; room: string }
  | { type: "say"; room: string; text: string };
type Client =
  | { type: "heard"; by: string; room: string; who: string; text: string }
  | { type: "joined"; user: string; room: string; on: string };

type User = Cmd | Line | Down;

export type Main = node.NodeEvent | Client;

type Member = { user: string; to: Pid<Line> };

/** Room `name`: the directory starts it on a node with `node.spawn`, which finds it by its name and
 * types — an exported function. */
export function room(this: Process<Room>, name: string, members: Member[]): void {
  receive {
    { type: "join", user, to, reply } => {
      monitor(to);
      reply.send(node.name());
      room(name, [...members, { user, to }]);
    },
    { type: "say", user, text } => {
      const all = members.map((m) => m.to);
      send(all, { type: "said", room: name, who: user, text });
      room(name, members);
    },
    { type: "DOWN", pid } => {
      const left = members.filter((m) => m.to !== pid);
      room(name, left);
    },
  }
}

function directory(this: Process<Dir>, rooms: Map<string, Pid<Room>>, turn: int): void {
  receive {
    { type: "where", name, gone, reply } => {
      const known = rooms.get(name);
      if (known !== null && known !== gone) {
        reply.send(known);
        return directory(rooms, turn);
      }
      const r = open(name, turn, 3, gone === null ? "" : node.of(gone));
      reply.send(r);
      directory(rooms.set(name, r), turn + 1);
    },
    { type: "DOWN", pid } => {
      // A room whose node is gone, if no member has asked for it since.
      const name = [...rooms.keys()].find((k) => rooms.get(k) === pid);
      if (name === null) return directory(rooms, turn);
      directory(rooms.set(name, open(name, turn, 3, node.of(pid))), turn + 1);
    },
  }
}

/** Starts room `name` on the node whose turn it is — or the next one, if that one cannot — and
 * watches it; not on node `not`, which the room is gone with (it may not know that yet). */
function open(this: Process<Dir>, name: string, turn: int, tries: int, not: string): Pid<Room> {
  if (tries === 0) panic(`room ${name} starts nowhere`);
  const all = [...node.nodes(), node.name()].filter((n) => n !== not);
  const r = node.spawn(all[turn % all.length], room, name, []);
  if (!r.ok) return open(name, turn + 1, tries - 1, not);
  monitor(r.value);
  return r.value;
}

function rooms(): Pid<Dir> {
  if (node.name() === "a") {
    const d = whereis<Dir>("rooms");
    if (d === null) panic("no directory of rooms");
    return d;
  }
  const f = node.find<Dir>("a", "rooms");
  if (!f.ok || f.value === null) panic("no directory of rooms on node a");
  return f.value;
}

/** A user waits for its client. */
function waiting(this: Process<User>, me: string): void {
  receive {
    { type: "hello", client } => user(me, client, new Map()),
  }
}

function user(
  this: Process<User>,
  me: string,
  client: Pid<Client>,
  mine: Map<string, Pid<Room>>,
): void {
  receive {
    { type: "join", room } => user(me, client, enter(me, client, mine, room, null)),
    { type: "say", room, text } => {
      const r = mine.get(room);
      if (r !== null) r.send({ type: "say", user: me, text });
      user(me, client, mine);
    },
    { type: "said", room, who, text } => {
      client.send({ type: "heard", by: me, room, who, text });
      user(me, client, mine);
    },
    { type: "DOWN", pid } => {
      // The node of a room is gone: the room is on another one now.
      const name = [...mine.keys()].find((k) => mine.get(k) === pid);
      if (name === null) return user(me, client, mine);
      user(me, client, enter(me, client, mine, name, mine.get(name)));
    },
    { type: "hello" } => user(me, client, mine),
  }
}

/** Joins room `name` where the directory says it is (`gone`: where it was). */
function enter(
  this: Process<User>,
  me: string,
  client: Pid<Client>,
  mine: Map<string, Pid<Room>>,
  name: string,
  gone: Pid<Room> | null,
): Map<string, Pid<Room>> {
  const r = rooms().call((reply) => ({ type: "where", name, gone, reply }), 5000);
  if (!r.ok) panic(r.error);
  monitor(r.value);
  // A call: what the client is told comes after the room has the user, and a line said in the
  // room after that goes to the user too. (Messages of different processes to the room have no
  // order between them: a `send` would not do.)
  const on = r.value.call((reply) => ({ type: "join", user: me, to: self(), reply }), 5000);
  if (!on.ok) panic(on.error);
  client.send({ type: "joined", user: me, room: name, on: on.value });
  return mine.set(name, r.value);
}

/** Nodes b and c: a user, until node a is gone. */
function child(this: Process<Main>, name: string, who: string, a: string): void {
  const me = node.start({ name, port: 0, secret: "chat" });
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

function waitUp(this: Process<Main>, n: int): void {
  if (n === 0) return;
  receive {
    { type: "nodeup" } => waitUp(n - 1),
    after 20000 => panic("the nodes did not come"),
  }
}

function userOn(on: string, name: string): Pid<User> {
  const f = node.find<User>(on, name);
  if (!f.ok || f.value === null) panic(`no user ${name} on node ${on}`);
  return f.value;
}

/** Prints `n` joins, in order of their users. */
function joined(this: Process<Main>, n: int, got: string[]): void {
  if (n === 0) {
    for (const j of got.sort()) console.log(j);
    return;
  }
  receive {
    { type: "joined", user, room, on } =>
      joined(n - 1, [...got, `${user} joined ${room} (on node ${on})`]),
    after 10000 => panic("no join"),
  }
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

/** The `nodedown` of node `n` and the join of the room it took, in either order. */
function moved(this: Process<Main>, n: string, down: bool, join: string): void {
  if (down && join !== "") {
    console.log(`node ${n} is gone`);
    console.log(join);
    return;
  }
  receive {
    { type: "nodedown", node } => moved(n, down || node === n, join),
    { type: "joined", user, room, on } =>
      moved(n, down, `${user} joined ${room} again (on node ${on})`),
    after 20000 => panic(`node ${n} did not go`),
  }
}

/** Exported: a test runs the example as it is. */
export function main(this: Process<Main>): void {
  const a = args();
  if (a.length === 3) return child(a[0], a[1], a[2]);
  const me = node.start({ name: "a", port: 0, secret: "chat" });
  if (!me.ok) panic(me.error);
  node.watch();
  spawn({ name: "rooms" }, directory, new Map(), 0);
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
  joined(3, []);
  for (const u of [bob, eve]) u.send({ type: "join", room: "random" });
  joined(2, []);
  ann.send({ type: "say", room: "general", text: "hi" });
  heard(3, "", []);
  eve.send({ type: "say", room: "random", text: "anyone?" });
  heard(2, "", []);
  // Node c goes with random and eve: bob joins random again, where it opens now.
  exec.kill(c.value);
  moved("c", false, "");
  ann.send({ type: "join", room: "random" });
  joined(1, []);
  ann.send({ type: "say", room: "random", text: "back" });
  heard(2, "", []);
  ann.send({ type: "say", room: "general", text: "still here" });
  heard(2, "", []);
  console.log("nodes:", node.nodes());
}
