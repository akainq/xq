// SQLite through calls to C functions. The library is sqlite3 (libsqlite3.so.0 on Linux);
// on Windows 10 and later, the built-in winsqlite3.dll will do. The functions that may wait for
// the disk are `blocking`: they run on a thread of the I/O pool, and the scheduler thread runs
// other processes meanwhile. sqlite3_exec takes an XQ function, which SQLite calls for each row:
// it runs in the calling process, during the call.
import * as ffi from "std/ffi";

declare library "sqlite3", "winsqlite3" {
  function sqlite3_libversion(): string;
  blocking function sqlite3_open(filename: string, out db: Pointer | null): i32;
  function sqlite3_close(db: Pointer): i32;
  function sqlite3_errmsg(db: Pointer): string;
  blocking function sqlite3_exec(
    db: Pointer,
    sql: string,
    row: ((arg: Pointer | null, columns: i32, values: Pointer, names: Pointer) => i32) | null,
    arg: Pointer | null,
    out error: Pointer | null,
  ): i32;
  function sqlite3_free(p: Pointer): void;
  function sqlite3_prepare_v2(
    db: Pointer,
    sql: string,
    bytes: i32,
    out stmt: Pointer | null,
    tail: Pointer | null,
  ): i32;
  function sqlite3_bind_int64(stmt: Pointer, i: i32, v: i64): i32;
  function sqlite3_bind_text(
    stmt: Pointer,
    i: i32,
    text: string,
    bytes: i32,
    destructor: Pointer,
  ): i32;
  blocking function sqlite3_step(stmt: Pointer): i32;
  function sqlite3_column_int64(stmt: Pointer, column: i32): i64;
  function sqlite3_column_text(stmt: Pointer, column: i32): string | null;
  function sqlite3_finalize(stmt: Pointer): i32;
}

const SQLITE_ROW = 100;

type Db = { handle: Pointer };
type User = { id: int; name: string; age: int };

function open(path: string): Result<Db> {
  const [rc, db] = sqlite3_open(path);
  if (db === null) return { ok: false, error: "sqlite3_open: out of memory" };
  if (rc !== 0) {
    const e = sqlite3_errmsg(db);
    sqlite3_close(db);
    return { ok: false, error: e };
  }
  return { ok: true, value: { handle: db } };
}

function exec(db: Db, sql: string): Result<null> {
  const [rc, err] = sqlite3_exec(db.handle, sql, null, null);
  if (rc === 0) return { ok: true, value: null };
  if (err === null) return { ok: false, error: `sqlite error ${rc}` };
  const msg = ffi.readCString(err);
  sqlite3_free(err);
  return { ok: false, error: msg };
}

/** Column `i` of a row SQLite gives to a function of sqlite3_exec: an array of C strings. */
function column(texts: Pointer, i: int): string {
  const p = ffi.readPointer(texts, i * 8);
  return p === null ? "NULL" : ffi.readCString(p);
}

/** Prints the rows of `sql`: SQLite calls the function for each. */
function show(db: Db, sql: string): void {
  const [_, err] = sqlite3_exec(
    db.handle,
    sql,
    (_, n, values, names) => {
      console.log(range(0, n).map((i) => `${column(names, i)}=${column(values, i)}`).join(" "));
      return 0;
    },
    null,
  );
  if (err !== null) {
    console.log(ffi.readCString(err));
    sqlite3_free(err);
  }
}

function insert(db: Db, name: string, age: int): Result<null> {
  const [rc, stmt] = sqlite3_prepare_v2(
    db.handle,
    "INSERT INTO users (name, age) VALUES (?, ?)",
    -1,
    null,
  );
  if (rc !== 0 || stmt === null) return { ok: false, error: sqlite3_errmsg(db.handle) };
  // SQLITE_TRANSIENT: SQLite copies the text right away.
  sqlite3_bind_text(stmt, 1, name, -1, ffi.pointer(-1));
  sqlite3_bind_int64(stmt, 2, age);
  sqlite3_step(stmt);
  sqlite3_finalize(stmt);
  return { ok: true, value: null };
}

function rows(stmt: Pointer, acc: User[]): User[] {
  if (sqlite3_step(stmt) !== SQLITE_ROW) return acc;
  const user = {
    id: sqlite3_column_int64(stmt, 0),
    name: sqlite3_column_text(stmt, 1) ?? "",
    age: sqlite3_column_int64(stmt, 2),
  };
  return rows(stmt, [...acc, user]);
}

function query(db: Db, sql: string): Result<User[]> {
  const [rc, stmt] = sqlite3_prepare_v2(db.handle, sql, -1, null);
  if (rc !== 0 || stmt === null) return { ok: false, error: sqlite3_errmsg(db.handle) };
  const users = rows(stmt, []);
  sqlite3_finalize(stmt);
  return { ok: true, value: users };
}

function main(): void {
  console.log("SQLite", sqlite3_libversion());
  const r = open(":memory:");
  if (!r.ok) {
    console.log(r.error);
    return;
  }
  const db = r.value;
 
  exec(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER)");
  const people: [string, int][] = [    
    ["Ann", 31],
    ["Boris", 27],
    ["Vera", 45],
  ];
  for (const [name, age] of people) {
    insert(db, name, age);
  }
  const q = query(db, "SELECT id, name, age FROM users WHERE age > 30 ORDER BY age");  
  if (q.ok) {
    for (const u of q.value) console.log(u.id, u.name, u.age);
  } else {
    console.log(q.error);
  }
  show(db, "SELECT name, age FROM users ORDER BY name");
  const bad = exec(db, "SELECT * FROM nowhere");
  console.log(bad.ok ? "ok" : bad.error);
  sqlite3_close(db.handle);
}
