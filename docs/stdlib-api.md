# Axiom standard library

Every public function, type and macro in Axiom's standard library, one
section per module. Start with [Modules at a glance](reference.md#modules-at-a-glance)
to choose a module.

Every listed declaration is public. An `effect` declaration is exported
without a `pub` keyword. The columns are:

- **Kind**: `value` for a function or constant, `struct`, `data`,
  `type` for an alias, `effect` or `macro`.
- **Type**: the source signature, such as `(-> Int Int)`, or the
  complete type alias declaration with its parameters.
- **Effects**: the compiler's inferred row. `Alloc` allocates, resets
  an arena or installs a handler. `IO` performs a syscall or external
  call, or reads command-line arguments. `Mut` changes memory. `Unsafe` exposes caller-established low-level obligations.
  `Spawn` creates a process or task, `Block` waits, and `Entropy` obtains
  randomness. Custom effects appear under their declared names.
  `incomplete` marks unresolved callable flow; that row is a lower bound.
  Callable arguments can add their own effects. A blank cell means no
  effects were inferred; a macro has no inferred row. See
  [effect inference limits](memory-model.md#1-execution-semantics) for the
  distinction between an inferred row and a guarantee.
- **Contracts**: the `pre` and `post` clauses checked on every call.
- **Summary**: the first paragraph of the `;;` doc comment above the
  definition. A blank cell is a name with no doc comment yet.

A module's `;;!` lines open its section.

This page is generated from the standard library by
`examples/axdoc/axdoc.ax`. Change its source or the generator to update it.

## `Agent.Tags`

`stdlib/Agent/Tags.ax` — 10 public names

Agent.Tags — reading what the compiler already says about a program.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Meta` | struct |  |  |  | One `#key` or `#key=value`. A bare flag - `#no_refactor` - has `val` empty, which `symHasTag` distinguishes from an absent key. |
| `Sym` | struct |  |  |  | One AXSYM line, parsed. |
| `axsymLine` | value | `(-> String (Option Sym))` | `Alloc,Mut` |  | One line. `None` for a blank line, for a line whose first byte is not a KIND letter, and for a line with no quoted type - which together are every non-AXSYM line a caller might feed in, including the `compilation failed` trailer and AXDL diagnostics on the same stream. |
| `axsymParse` | value | `(-> String (Vec Sym))` | `Alloc,Mut` |  | A whole AXSYM stream. Lines that are not AXSYM are skipped, so the caller may pass the compiler's output unfiltered. |
| `symTag` | value | `(-> Sym String String)` |  |  | The value of the LAST `#key` on the line, or empty. Empty is also what a bare flag answers, so a caller distinguishing "absent" from "present with no value" wants `symHasTag`. |
| `symHasTag` | value | `(-> Sym String Bool)` |  |  | Whether the line carries `#key` at all, with or without a value. |
| `symEffects` | value | `(-> Sym String)` |  |  | The effect row the CHECKER derived - not what the author claimed. Empty when the declaration performs none. |
| `symDerivedPure` | value | `(-> Sym Bool)` |  |  | True when the checker derived no effects at all. This is a statement about the ANALYSIS, not a guarantee about the program: an effect reached through a function value in memory is not in the row, and a built-in effect named by an enclosing `handle` is subtracted from it. A policy that treats this as proof of purity is reading a lower bound as an upper one. |
| `symAgentTag` | value | `(-> Sym String String)` | `Alloc,Mut` |  | The `agent:*` namespace, which the compiler records and does not check. `(symAgentTag s "rewrite")` reads `#agent:rewrite`. |
| `symHasAgentTag` | value | `(-> Sym String Bool)` | `Alloc,Mut` |  | Whether the line carries `#agent:k`, with or without a value. |

## `Axqlite`

`stdlib/Axqlite.ax` — 75 public names

Axqlite - an embedded, single-file, transactional database.

    (axqWith "app.db" openOptions
      (lambda (db)
        {
          (axqExec db "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER)")?
          (axqRunOn db (axqlInsert users (name age) (values (text "Ada") (int 36))))?
          (for r in (axqAll db (axqlSelect users (id name) (where (> age (int 30))))?)
            (println (rowTextOr r "name" "?")))
          (Ok 0)
        }))

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `OpenOptions` | struct |  |  |  | How `axqOpen` opens a database: whether a missing file becomes a new database, whether the connection may only read, and how many 4096-byte pages its cache holds. |
| `openOptions` | value | `OpenOptions` | `Alloc` |  | The defaults: create the file when it's missing, read and write, and cache 256 pages (1 MiB). |
| `readOnlyOptions` | value | `OpenOptions` | `Alloc` |  | Open a database that must already exist, for reading only, with the same cache as `openOptions`. Every write on it is `axqReadOnly`. |
| `Connection` | struct |  |  |  | An open database. |
| `Statement` | struct |  |  |  | A prepared statement: its text, checked against the schema when it was prepared, and parsed again against the current schema each time it runs. |
| `Transaction` | struct |  |  |  | An open transaction, from `axqBegin`. |
| `axqOpen` | value | `(-> String OpenOptions (Result Connection Error))` | `Alloc,IO,Mut,Unsafe` |  | Open the database at `path`. A missing file is created when `opts.create` is true, and is `axqIoFailed` otherwise; a file that isn't an AXQLite database is `axqNotADatabase`. |
| `axqClose` | value | `(-> Connection (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Close the connection, rolling back a transaction it has open. Closing it again answers `Ok`, as `fileClose` does; any other later use stops the program with status 85. Statements prepared on it must still be finalized. |
| `axqWith` | value | `(-> String OpenOptions (-> Connection (Result a Error)) (Result a Error))` | `Alloc,IO,Mut` |  | Open the database at `path`, run `f` on the connection, and close the connection whatever `f` answers. The answer is `f`'s, unless closing fails and `f` succeeded, in which case the close's error is the answer. This is the usual way to use a database: one `axqWith` in place of an `axqOpen` match and an `axqClose`. |
| `axqValueText` | value | `(-> Value String)` | `Alloc,Mut` |  | A value written as AXQL would write it as a literal: an INTEGER in decimal, a REAL in the shortest form that reads back exactly, TEXT in single quotes with `''` for a quote, a BLOB as x'hex', and NULL. |
| `axqlQuoteText` | value | `(-> String String)` | `Alloc,Mut` |  | `s` as an AXQL text literal: in single quotes, each quote doubled. |
| `Row` | struct |  |  |  | One result row: the column names, shared by every row of a result, and the values. |
| `Rows` | struct |  |  |  | A whole result: its column names and its rows. |
| `rowLen` | value | `(-> Row Int)` |  |  | How many columns a row has. |
| `rowName` | value | `(-> Row Int (Result String Error))` | `Alloc,Mut` |  | The name of column `i`, from 0. |
| `rowIndex` | value | `(-> Row String (Result Int Error))` | `Alloc,Mut` |  | The number of the column named `name`, compared without regard to ASCII case; the first when two share it. |
| `rowValue` | value | `(-> Row Int (Result Value Error))` | `Alloc,Mut` |  | The value in column `i`. |
| `rowIsNull` | value | `(-> Row Int (Result Bool Error))` | `Alloc,Mut` |  | Whether column `i` is NULL. |
| `rowInt` | value | `(-> Row Int (Result Int Error))` | `Alloc,Mut` |  | Column `i` as an INTEGER. Any other type, NULL included, is `axqType`. |
| `rowReal` | value | `(-> Row Int (Result Float Error))` | `Alloc,Mut` |  | Column `i` as a REAL. An INTEGER is converted, as a REAL column converts one; any other type is `axqType`. |
| `rowText` | value | `(-> Row Int (Result String Error))` | `Alloc,Mut` |  | Column `i` as TEXT. |
| `rowBlob` | value | `(-> Row Int (Result String Error))` | `Alloc,Mut` |  | Column `i` as a BLOB's bytes. |
| `rowValueNamed` | value | `(-> Row String (Result Value Error))` | `Alloc,Mut` |  | The value of the column named `name`. |
| `rowIsNullNamed` | value | `(-> Row String (Result Bool Error))` | `Alloc,Mut` |  | Whether the column named `name` is NULL. |
| `rowIntNamed` | value | `(-> Row String (Result Int Error))` | `Alloc,Mut` |  | The column named `name` as an INTEGER. |
| `rowRealNamed` | value | `(-> Row String (Result Float Error))` | `Alloc,Mut` |  | The column named `name` as a REAL. |
| `rowTextNamed` | value | `(-> Row String (Result String Error))` | `Alloc,Mut` |  | The column named `name` as TEXT. |
| `rowBlobNamed` | value | `(-> Row String (Result String Error))` | `Alloc,Mut` |  | The column named `name` as a BLOB's bytes. |
| `rowIntOr` | value | `(-> Row String Int Int)` | `Alloc,Mut` |  | The column named `name` as an INTEGER, or `default` when it is not one: NULL, another type, or no such column. These four readers are the everyday form, for a value you can fall back on; the `Result` readers above are for telling the cases apart. |
| `rowRealOr` | value | `(-> Row String Float Float)` | `Alloc,Mut` |  | The column named `name` as a REAL, or `default` when it is not one. |
| `rowTextOr` | value | `(-> Row String String String)` | `Alloc,Mut` |  | The column named `name` as TEXT, or `default` when it is not one. |
| `rowBlobOr` | value | `(-> Row String String String)` | `Alloc,Mut` |  | The column named `name` as a BLOB's bytes, or `default` when it is not one. |
| `axqBegin` | value | `(-> Connection (Result Transaction Error))` | `Alloc,IO,Mut,Unsafe` |  | Open a transaction. Statements then run inside it until `axqCommit` or `axqRollback`; one that fails is undone and the transaction stays open. No lock is taken until the first statement needs one. |
| `axqCommit` | value | `(-> Transaction (Result Int Error))` | `Alloc,IO,Mut` |  | Commit the transaction: durable when this answers `Ok`. A transaction COMMIT or ROLLBACK already ended is `axqMisuse`. |
| `axqRollback` | value | `(-> Transaction (Result Int Error))` | `Alloc,IO,Mut` |  | Roll the transaction back. |
| `axqTransaction` | value | `(-> Connection (-> Connection (Result a Error)) (Result a Error))` | `Alloc,IO,Mut` |  | Run `f` in a transaction: commit when it answers `Ok`, roll back when it answers `Err`, and answer what it answered (or the commit's failure). `f` must not end the transaction itself. |
| `axqInTransaction` | value | `(-> Connection Bool)` |  |  | Whether a transaction is open. |
| `axqLastInsertRowid` | value | `(-> Connection Int)` |  |  | The rowid the last successful INSERT on this connection gave its last row, or 0 before the first. |
| `axqChanges` | value | `(-> Connection Int)` |  |  | The rows the last successful INSERT, UPDATE or DELETE changed. |
| `axqExec` | value | `(-> Connection String (Result Int Error))` | `Alloc,IO,Mut` |  | Run one statement that takes no parameters. A SELECT runs and its rows are dropped. Answers the rows changed. |
| `axqExecBatch` | value | `(-> Connection String (Result Int Error))` | `Alloc,IO,Mut` |  | Run a script of statements separated by `;`, such as a migration, in one transaction: all of them or none. Outside a transaction it opens and commits its own; inside one, a failure undoes the whole script and leaves the transaction open. The script may not hold BEGIN, COMMIT or ROLLBACK, and nothing runs if any statement fails to parse. Answers the rows changed in total. |
| `axqStatementText` | value | `(-> Statement String)` | `Alloc,Mut,Unsafe` |  | The statement's text, copied into the caller's arena. |
| `axqParamCount` | value | `(-> Statement Int)` |  |  | How many parameters the statement takes. |
| `axqPrepare` | value | `(-> Connection String (Result Statement Error))` | `Alloc,IO,Mut,Unsafe` |  | Parse `text` and check its table and column names against the current schema. The statement parses its text again each time it runs, so a schema change after this re-prepares it; a statement whose table is gone then answers `axqSchema`. |
| `axqFinalize` | value | `(-> Statement (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Finalize the statement, freeing its mapping. Finalizing it again answers `Ok`; any other later use stops the program with status 85. |
| `axqParamIndex` | value | `(-> Statement String (Result Int Error))` | `Alloc,Mut` |  | The index in a statement's parameter vector (from 0) of the named parameter `name`, written with its colon: `":id"`. |
| `axqRun` | value | `(-> Statement (Vec Value) (Result Int Error))` | `Alloc,IO,Mut` |  | Run a statement that returns no rows with `params`, one per parameter. Answers the rows changed. A SELECT is `axqMisuse`: use `axqQuery` or `axqQueryEach`. |
| `axqQuery` | value | `(-> Statement (Vec Value) (Result Rows Error))` | `Alloc,IO,Mut` |  | Run a SELECT with `params` and answer all its rows. |
| `axqQueryEach` | value | `(-> Statement (Vec Value) (-> Row (Result Bool Error)) (Result Int Error))` | `Alloc,IO,Mut` |  | Run a SELECT with `params`, calling `f` with each row as it is produced. Stops when `f` answers `Ok false` or `Err`, and answers that `Err`, or else the number of rows `f` was called with. |
| `axqSql` | value | `(-> String Query)` | `Alloc,Mut` |  | A statement's text with no parameters: `(axqSql "SELECT 1")` is `(Query :text "SELECT 1" :params vecNew)` without building the empty vector. Give the parameters with `(Query :text text :params params)`. |
| `axqRunOn` | value | `(-> Connection Query (Result Int Error))` | `Alloc,IO,Mut` |  | Run a query that returns no rows. Answers the rows changed. |
| `axqQueryOn` | value | `(-> Connection Query (Result Rows Error))` | `Alloc,IO,Mut` |  | Run a query and answer all its rows. |
| `axqAll` | value | `(-> Connection Query (Result (Vec Row) Error))` | `Alloc,IO,Mut` |  | Run a query and answer just its rows, without the `Rows` wrapper: the everyday form when the column names are not needed. |
| `axqQueryEachOn` | value | `(-> Connection Query (-> Row (Result Bool Error)) (Result Int Error))` | `Alloc,IO,Mut` |  | Run a query, calling `f` with each row as it is produced, as `axqQueryEach` does. |
| `axqQueryMap` | value | `(-> Connection Query (-> Row (Result a Error)) (Result (Vec a) Error))` | `Alloc,IO,Mut` |  | Run a query and answer `f` of each row, stopping at the first `Err` from the query or from `f`. |
| `axqQueryOne` | value | `(-> Connection Query (Result (Option Row) Error))` | `Alloc,IO,Mut` |  | The first row a query answers, or `None` when it answers none. The scan stops at that row. |
| `axqQueryInt` | value | `(-> Connection Query (Result Int Error))` | `Alloc,IO,Mut` |  | The INTEGER in the first column of the first row a query answers, such as `SELECT count(*) FROM t`. No row is `axqNotFound`; NULL or another type is `axqType`. |
| `axqQueryText` | value | `(-> Connection Query (Result String Error))` | `Alloc,IO,Mut` |  | The TEXT in the first column of the first row a query answers. No row is `axqNotFound`; NULL or another type is `axqType`. |
| `ColumnInfo` | struct |  |  |  | One column of a table, as `axqColumns` describes it: its name, its type as AXQL spells it, whether it is NOT NULL and whether it is the PRIMARY KEY, the table it links to ("" for none), and the column as its CREATE TABLE wrote it, with any DEFAULT and CHECK. |
| `IndexInfo` | struct |  |  |  | One index of a table: its name, whether it is UNIQUE, and its columns in order. |
| `axqTables` | value | `(-> Connection (Result (Vec String) Error))` | `Alloc,IO,Mut` |  | The names of the database's tables, in the order they were created. |
| `axqColumns` | value | `(-> Connection String (Result (Vec ColumnInfo) Error))` | `Alloc,IO,Mut` |  | The columns of table `table`, in order. A table that doesn't exist is `axqSchema`. |
| `axqIndexes` | value | `(-> Connection String (Result (Vec IndexInfo) Error))` | `Alloc,IO,Mut` |  | The indices of table `table`, in the order they were created. |
| `axqDump` | value | `(-> Connection (Result String Error))` | `Alloc,IO,Mut` |  | The whole database as an AXQL script: every CREATE TABLE, then each table's rows as INSERTs with their rowids, then every CREATE INDEX. `(axqExecBatch db script)` on an empty database loads it back. Tables that link to each other in a cycle can't be ordered, and are `axqSchema`. |
| `RowReader` | struct |  |  |  | A row being read into a record: the row, and the first failure. Each read answers a stand-in value after a failure, so a record can be built in one expression and checked once at the end. |
| `axqlReader` | value | `(-> Row RowReader)` | `Alloc` |  | A reader over `row`. |
| `axqlReadInt` | value | `(-> RowReader String Int)` | `Alloc,Mut` |  | The column named `name` as an INTEGER, or 0 after recording why not. |
| `axqlReadReal` | value | `(-> RowReader String Float)` | `Alloc,Mut` |  | The column named `name` as a REAL, or 0.0 after recording why not. |
| `axqlReadText` | value | `(-> RowReader String String)` | `Alloc,Mut` |  | The column named `name` as TEXT, or "" after recording why not. |
| `axqlReadBlob` | value | `(-> RowReader String String)` | `Alloc,Mut` |  | The column named `name` as a BLOB's bytes, or "" after recording why not. |
| `axqlReadOptInt` | value | `(-> RowReader String (Option Int))` | `Alloc,Mut` |  | The column named `name`: `None` for NULL, else its INTEGER. |
| `axqlReadOptReal` | value | `(-> RowReader String (Option Float))` | `Alloc,Mut` |  | The column named `name`: `None` for NULL, else its REAL. |
| `axqlReadOptText` | value | `(-> RowReader String (Option String))` | `Alloc,Mut` |  | The column named `name`: `None` for NULL, else its TEXT. |
| `axqlReadOptBlob` | value | `(-> RowReader String (Option String))` | `Alloc,Mut` |  | The column named `name`: `None` for NULL, else its BLOB's bytes. |
| `axqlReaderDone` | value | `(-> RowReader a (Result a Error))` | `Alloc` |  | `value` when every read went well, else the first failure. |

## `Axqlite.AxqlAst`

`stdlib/Axqlite/AxqlAst.ax` — 44 public names

Axqlite.AxqlAst - the parsed form of one AXQL statement.

    (axqlParse "SELECT name FROM users WHERE id = ?")
        ; (Ok (SSelect ...)) with one parameter

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `opAdd` | value | `Int` |  |  | The binary operators an `EBin` carries: `+`. |
| `opSub` | value | `Int` |  |  | `-`. |
| `opMul` | value | `Int` |  |  | `*`. |
| `opDiv` | value | `Int` |  |  | `/`. |
| `opMod` | value | `Int` |  |  | `%`. |
| `opEq` | value | `Int` |  |  | `=`. |
| `opNe` | value | `Int` |  |  | `!=`. |
| `opLt` | value | `Int` |  |  | `<`. |
| `opLe` | value | `Int` |  |  | `<=`. |
| `opGt` | value | `Int` |  |  | `>`. |
| `opGe` | value | `Int` |  |  | `>=`. |
| `opAnd` | value | `Int` |  |  | `AND`. |
| `opOr` | value | `Int` |  |  | `OR`. |
| `opConcat` | value | `Int` |  |  | `\|\|`, text concatenation. |
| `opIsComparison` | value | `(-> Int Bool)` |  |  | Whether `op` is one of the six comparisons. |
| `opIsArithmetic` | value | `(-> Int Bool)` |  |  | Whether `op` is one of the five arithmetic operators. |
| `opText` | value | `(-> Int String)` |  |  | The operator as AXQL spells it, for messages. |
| `typeInteger` | value | `Int` |  |  | The four column types, as a `ColumnDef` records them: INTEGER. |
| `typeReal` | value | `Int` |  |  | REAL. |
| `typeText` | value | `Int` |  |  | TEXT. |
| `typeBlob` | value | `Int` |  |  | BLOB. |
| `typeNull` | value | `Int` |  |  | The type of an expression whose value is always NULL, such as the literal `NULL`. Never a column's type. |
| `typeName` | value | `(-> Int String)` |  |  | A type's name as a statement spells it. |
| `Expr` | data |  |  |  | An expression. Every variant that can fail at run time carries the byte offset of its operator, so a message can say where. |
| `ColumnDef` | struct |  |  |  | One column of a `CREATE TABLE`: its name, type, whether it is NOT NULL and whether it is the PRIMARY KEY, the table it links to ("" for none), its DEFAULT and CHECK expressions, its text as the statement wrote it, and where in that text the linked table's name starts (-1 for none). |
| `aggCount` | value | `Int` |  |  | The aggregates: `count`, `sum`, `avg`, `min` and `max`. |
| `aggSum` | value | `Int` |  |  | `sum(e)`. |
| `aggAvg` | value | `Int` |  |  | `avg(e)`. |
| `aggMin` | value | `Int` |  |  | `min(e)`. |
| `aggMax` | value | `Int` |  |  | `max(e)`. |
| `aggName` | value | `(-> Int String)` |  |  | An aggregate's name as AXQL spells it. |
| `axqlEditDistance` | value | `(-> String String Int)` | `Alloc,Mut` |  | How many single-byte edits, ignoring ASCII case, turn `a` into `b`, counted up to 3. An edit inserts, deletes or changes a byte, or swaps two neighbours. |
| `axqlNear` | value | `(-> String String Bool)` | `Alloc,Mut` |  | Whether `name` is near enough `other` to suggest it: within two edits, or one for a name of four bytes or fewer, and fewer edits than `name` has bytes. |
| `axqlFunctionNames` | value | `String` |  |  | The functions an expression may call, by their lower-case names, as one string for messages. |
| `axqlFunMinArgs` | value | `(-> String Int)` | `Alloc,Mut` |  | The fewest arguments function `name` (in lower case) takes, or -1 when there is no such function. |
| `axqlFunMaxArgs` | value | `(-> String Int)` | `Alloc,Mut` |  | The most arguments function `name` takes, or -1 when there is no such function. `coalesce`, `min` and `max` take up to 32. |
| `SelectItem` | struct |  |  |  | One item of a `SELECT` list: the expression, the name `AS` gave it ("" when none), and the text the statement wrote it with. |
| `OrderTerm` | struct |  |  |  | One `ORDER BY` term. |
| `Select` | struct |  |  |  | A `SELECT`. `star` is true for `SELECT *`, and then `items` holds only the `link.*` items written after it. `from` is "" when the statement has no FROM clause. |
| `Stmt` | data |  |  |  | One statement. |
| `Parsed` | struct |  |  |  | CREATE TABLE [IF NOT EXISTS] name (columns) DROP TABLE [IF EXISTS] name CREATE [UNIQUE] INDEX [IF NOT EXISTS] name ON table (columns): unique, ifNotExists, name, table, columns DROP INDEX [IF EXISTS] name INSERT INTO table [(columns)] VALUES (row), ...: the columns are empty when the statement names none UPSERT INTO table [(columns)] VALUES (row), ...: the same shape; a row whose rowid exists is updated in the columns given ALTER TABLE table ADD COLUMN column ALTER TABLE table RENAME TO name ALTER TABLE table DROP COLUMN column ALTER TABLE table RENAME COLUMN old TO new UPDATE table SET column = expr, ... [WHERE expr] DELETE FROM table [WHERE expr] A parsed statement with what the parameter scan found: how many parameters it takes, the names of named ones in index order (empty when it uses `?` or `?N`), and the statement's own text, from its first token to its last. |
| `stmtIsQuery` | value | `(-> Stmt Bool)` |  |  | Whether a statement answers rows. |
| `stmtIsDdl` | value | `(-> Stmt Bool)` |  |  | Whether a statement changes the schema. |
| `axqlPosText` | value | `(-> String Int String)` | `Alloc,Mut` |  | "line L, column C" for byte offset `at` of `src`. |

## `Axqlite.AxqlEval`

`stdlib/Axqlite/AxqlEval.ax` — 27 public names

Axqlite.AxqlEval - what AXQL's operators do to values.

    (axqlCompare (VInt 2) (VReal 2.5))       ; (Ok -1): numeric order
    (axqlArith opAdd (VInt 1) VNull)          ; (Ok VNull)
    (axqlArith opAdd (VInt intMax) (VInt 1))  ; (Err ...) axqArithmetic

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `tvFalse` | value | `Int` |  |  | FALSE, as a truth value. |
| `tvTrue` | value | `Int` |  |  | TRUE. |
| `tvNull` | value | `Int` |  |  | NULL, as a truth value. |
| `axqlTruth` | value | `(-> Value (Result Int Error))` | `Alloc` |  | The truth of a value: a number is TRUE when it isn't zero, NULL is NULL, and TEXT or BLOB is `axqType`. |
| `truthValue` | value | `(-> Int Value)` | `Alloc` |  | A truth value as the INTEGER or NULL a statement sees. |
| `axqlValueType` | value | `(-> Value Int)` |  |  | The type of a value: one of the four column types, or `typeNull`. |
| `axqlCompareIntReal` | value | `(-> Int Float Int)` |  |  | -1, 0 or 1 as INTEGER `i` is below, equal to or above REAL `r`, exactly. `r` is never NaN: NaN isn't a value a statement can hold. |
| `axqlCompare` | value | `(-> Value Value (Result Int Error))` | `Alloc,Mut` |  | -1, 0 or 1 as `a` is below, equal to or above `b`, for two non-NULL values of comparable types: two numbers, two TEXTs or two BLOBs. Anything else is `axqType`. |
| `axqlSortCompare` | value | `(-> Value Value Int)` | `Alloc,Mut` |  | The order ORDER BY sorts in: NULL first, then numbers, then TEXT, then BLOB, each kind in its own order. Total, so it never fails. |
| `axqlComparison` | value | `(-> Int Value Value (Result Value Error))` | `Alloc,Mut` |  | The six comparisons over two values, with NULL on either side giving NULL. |
| `axqlArith` | value | `(-> Int Value Value (Result Value Error))` | `Alloc,Mut` |  | One of `+ - * / %` over two values. NULL on either side gives NULL. |
| `axqlNegate` | value | `(-> Value (Result Value Error))` | `Alloc,Mut` |  | Unary minus. The most negative INTEGER has no negation. |
| `axqlLike` | value | `(-> String String Bool)` | `Alloc,Mut` |  | Whether TEXT `s` matches LIKE pattern `p`: `%` matches any run of bytes, `_` any one byte, `\` makes the next byte literal, and every other byte matches itself, case and all. |
| `axqlApply` | value | `(-> String (Vec Value) (Result Value Error))` | `Alloc,Mut` |  | Function `name` (in lower case) applied to argument values `vs`, whose number the parser has checked. Every function but `coalesce`, `nullif` and `typeOf` answers NULL when an argument is NULL. |
| `axqlEval` | value | `(-> Expr (Vec Value) Int (Vec Value) (Result Value Error))` | `Alloc,Mut` |  | Evaluate `e` over one row: `row` holds the table's columns and `rowid` its rowid. `params` are the bound parameters. An unbound name is a refusal: the binder rewrites every name before evaluation. |
| `axqlEvalAll` | value | `(-> (Vec Expr) (Vec Value) Int (Vec Value) (Result (Vec Value) Error))` | `Alloc,Mut` |  | Every expression of `es` evaluated over one row, or the first failure. |
| `axqlConjuncts` | value | `(-> Expr (Vec Expr))` | `Alloc,Mut` |  | The top-level AND terms of `e`, left to right. |
| `axqlKeep` | value | `(-> (Vec Expr) (Vec Value) Int (Vec Value) (Result Bool Error))` | `Alloc,Mut` |  | Whether a row passes a WHERE given as its AND terms. The row is dropped when any term is FALSE or NULL, whatever the others do; a term's failure is the answer only when no term drops the row. |
| `axqlTypeOf` | value | `(-> String Expr (Vec Int) (Vec Value) (Result Int Error))` | `Alloc,Mut` |  | The type `e` has whenever it isn't NULL, given the types of the table's columns (the rowid is INTEGER) and the bound parameters. `typeNull` means always NULL. A mismatch is `axqType`, named with its place in `src`, before any row is read. |
| `axqlFold` | value | `(-> Expr (Vec Value) (Result Expr Error))` | `Alloc,Mut` |  | `e` with each largest subexpression that names no column replaced by its value. Those are evaluated once, before any row is read, so a failure among them fails the statement even when no row would have reached it. |
| `axqlIsConstant` | value | `(-> Expr Bool)` |  |  | Whether `e` names no column: a literal, a parameter, or operators over those. |
| `axqlChildren` | value | `(-> Expr (Vec Expr))` | `Alloc,Mut` |  | The expressions directly inside `e`, left to right. |
| `axqlHasAgg` | value | `(-> Expr Bool)` | `Alloc,Mut` |  | Whether `e` holds an aggregate anywhere. |
| `axqlAggPos` | value | `(-> Expr Int)` | `Alloc,Mut` |  | The offset of the first aggregate in `e`, or -1. |
| `axqlHasParamOrLink` | value | `(-> Expr Bool)` | `Alloc,Mut` |  | Whether `e` holds a parameter or a link path anywhere: what a DEFAULT or CHECK stored in the schema can't hold. |
| `axqlColumnsRead` | value | `(-> Expr (Vec Int) Int)` | `Alloc,Mut` |  | Every column number a bound `e` reads, pushed onto `out`. |
| `axqlExprEq` | value | `(-> Expr Expr Bool)` | `Alloc,Mut` |  | Whether two bound expressions are written the same way. |

## `Axqlite.AxqlExec`

`stdlib/Axqlite/AxqlExec.ax` — 14 public names

Axqlite.AxqlExec - planning and running one AXQL statement.

    (axqlPlanSelect ex sel)            ; (Ok <SelectPlan>): bound, typed, planned
    (axqlRunSelect ex plan onRow)      ; calls onRow with each result row
    (axqlRunWrite ex parsed)           ; INSERT, UPDATE, DELETE or DDL

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Undo` | data |  |  |  | A change to reverse when a statement fails: put back an old value, delete a key the statement added, drop a tree it created, or give up (a dropped tree can't come back). |
| `Exec` | struct |  |  |  | One statement's context: the pager, the statement's text (for messages), its parameters, the undo log, what it did, and the rows it wrote to a table with links, whose links are checked when it ends. |
| `axqlExec` | value | `(-> Pager String (Vec Value) Bool Exec)` | `Alloc,Mut` |  | A context for running the statement `src` with `params`. |
| `axqlUndo` | value | `(-> Pager (Vec Undo) (Result Int Error))` | `Alloc,IO,Mut` |  | Reverse every change `undo` records, newest first. `Err` when one of them can't be reversed; the caller then rolls back the transaction. |
| `Access` | data |  |  |  | How a statement finds its rows. |
| `RowRef` | struct |  |  |  | A row as a scan meets it: its rowid and its values. |
| `GroupPlan` | struct |  |  |  | How a grouped SELECT works out its rows: the GROUP BY terms, the aggregates it computes, and its select list, HAVING and ORDER BY with each aggregate replaced by a parameter past the statement's own, which carries the aggregate's value for the group. |
| `SelectPlan` | struct |  |  |  | A planned SELECT. `fetch` marks the links whose rows it reads, and `group` is there when it groups its rows. |
| `axqlPlanNames` | value | `(-> SelectPlan (Vec String))` |  |  | The column names a SELECT answers. |
| `axqlPlanSelect` | value | `(-> Exec Schema Select (Result SelectPlan Error))` | `Alloc,Mut` |  | Bind, check, fold and plan a SELECT. Needs a lock. |
| `axqlRunSelect` | value | `(-> Exec SelectPlan (-> (Vec Value) (Result Bool Error)) (Result Int Error))` | `Alloc,IO,Mut` |  | Run a planned SELECT, calling `onRow` with each result row. Stops early when `onRow` answers `Ok false`. Answers the rows returned. |
| `axqlMaxColumns` | value | `Int` |  |  | The most columns a table may have. |
| `axqlRunWrite` | value | `(-> Exec Stmt String (Result Int Error))` | `Alloc,IO,Mut` |  | Run an INSERT, UPDATE, DELETE or DDL statement inside the caller's write transaction. Answers the rows it changed (0 for DDL). |
| `axqlCheckNames` | value | `(-> Exec Schema Stmt (Result Int Error))` | `Alloc,Mut` |  | Check that a statement's names resolve against the current schema, without running it: the check `axqPrepare` makes. DDL is checked when it runs. |

## `Axqlite.AxqlMacro`

`stdlib/Axqlite/AxqlMacro.ax` — 42 public names

Axqlite.AxqlMacro - AXQL statements written as Axiom forms.

    (axqlSelect users (id name) (where (> age (int minAge))) (orderBy (age desc)) (limit 10))
        ; (Query :text "SELECT id, name FROM users WHERE age > ? ORDER BY age DESC LIMIT ?"
        ;        :params [(VInt minAge) (VInt 10)])
    (axqlInsert users (name age) (values (text "Ada") (int 36)))
    (axqlUpdate users (assign (age (+ age (int 1)))) (where (= id (int uid))))
    (axqlDelete users (where (< age (int 18))))
    (axqlCreateTable IF NOT EXISTS users (id INTEGER PRIMARY KEY) (name TEXT NOT NULL))
    (axqlTable User users (id RowId) (name String) (age OptInt))

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Query` | struct |  |  |  | A statement's text with the values of its parameters, in order. The `axql...` macros build one; `axqRunOn`, `axqQueryOn` and `axqQueryEachOn` run one. |
| `QueryBuilder` | struct |  |  |  | A query being written: the text in pieces, and the parameters so far. The statement macros make one, append to it left to right, and finish it; a program has no need to touch one. |
| `axqlBuilder` | value | `QueryBuilder` | `Alloc,Mut` |  | An empty builder. |
| `axqlPut` | value | `(-> QueryBuilder String Int)` | `Alloc,Mut` |  | Append text the macro spells. |
| `axqlPutName` | value | `(-> QueryBuilder String Int)` | `Alloc,Mut` |  | Append a name, in double quotes when AXQL needs them. |
| `axqlPutParam` | value | `(-> QueryBuilder Value Int)` | `Alloc,Mut` |  | Append a parameter: `?` in the text, `v` in the parameters. |
| `axqlFinish` | value | `(-> QueryBuilder Query)` | `Alloc,Mut` |  | The finished query. |
| `axqlQuoteName` | value | `(-> String String)` | `Alloc,Mut` |  | `name` as AXQL writes a name: bare when it can be, else in double quotes with each `"` inside doubled. |
| `RowId` | type | `(type RowId Int)` |  |  | A field that is its table's INTEGER PRIMARY KEY, the rowid. |
| `Bytes` | type | `(type Bytes String)` |  |  | A field holding a BLOB's bytes. |
| `OptInt` | type | `(type OptInt (Option Int))` |  |  | An INTEGER column that may be NULL: `None` is NULL. |
| `OptFloat` | type | `(type OptFloat (Option Float))` |  |  | A REAL column that may be NULL. |
| `OptString` | type | `(type OptString (Option String))` |  |  | A TEXT column that may be NULL. |
| `OptBytes` | type | `(type OptBytes (Option String))` |  |  | A BLOB column that may be NULL. |
| `axqlAddParam` | value | `(-> QueryBuilder Value Int)` | `Alloc,Mut` |  | Append a parameter's value with no `?`, for a statement whose text already holds its marks. |
| `axqlOptIntValue` | value | `(-> (Option Int) Value)` | `Alloc` |  | An optional INTEGER as a parameter: `None` is NULL. |
| `axqlOptFloatValue` | value | `(-> (Option Float) Value)` | `Alloc` |  | An optional REAL as a parameter. |
| `axqlOptTextValue` | value | `(-> (Option String) Value)` | `Alloc` |  | An optional TEXT as a parameter. |
| `axqlOptBlobValue` | value | `(-> (Option String) Value)` | `Alloc` |  | An optional BLOB as a parameter. |
| `axqlPutNameOf` | macro |  |  |  | A name, as `axqlPutName` writes it, from an identifier. |
| `axqlColumnOf` | macro |  |  |  | An `axqlTable` field as its column. |
| `axqlPutColumn` | value | `(-> QueryBuilder String String Int)` | `Alloc,Mut` |  | Append `name TYPE...`. |
| `axqlFieldValue` | macro |  |  |  | An `axqlTable` field's value as a parameter. |
| `axqlReadField` | macro |  |  |  | An `axqlTable` field read from a row by its column's name. |
| `axqlUpdate` | macro |  |  |  | An UPDATE of table `t`: `(assign (column e) ...)`, then an optional `(where e)`. The word is `assign` because `set` is Axiom's own. |
| `axqlDelete` | macro |  |  |  | A DELETE from table `t`, with an optional `(where e)`. |
| `axqlDropTable` | macro |  |  |  | A DROP TABLE, with an optional `IF EXISTS`. |
| `axqlCreateIndex` | macro |  |  |  | A CREATE INDEX: optional `UNIQUE` and `IF NOT EXISTS`, the index's name, `ON`, the table, and its columns. |
| `axqlDropIndex` | macro |  |  |  | A DROP INDEX, with an optional `IF EXISTS`. |
| `axqlMark` | macro |  |  |  | One `?`, for a field of `axqlTable`'s INSERT. |
| `axqlFieldColumn` | macro |  |  |  | One `(name Type)` field of `axqlTable` as its column. |
| `axqlTableRest` | macro |  |  |  | The second half of `axqlTable`, which it invokes: what it declares once the struct exists, because a struct's fields can be read by name only through `syntax/fields`, which answers only for a struct already declared. It is public because a declaration macro's own invocation is resolved where `axqlTable` is used; a program has no need to call it. |
| `axqlSpread` | macro |  |  |  | Spread a parenthesised list into the arguments of a helper: `(axqlSpread k qb (a b c))` is `(k qb a b c)`. Public because the statement macros that use it are expanded where they are invoked. |
| `axqlSelect` | macro |  |  |  | A SELECT from table `t`: its select list (`*`, one column, or a list of columns and `(alias e name)` items), then its clauses in this order, each optional: `(where e)`, `(groupBy e ...)` with up to three terms, `(having e)`, `(orderBy term ...)`, `(limit n)`, and `(offset n)` after a `limit`. `n` is an Axiom `Int`, bound as a parameter. |
| `axqlFieldNames` | macro |  |  |  | `(names f ...)`, spread: names separated by `, `. Public, as the helpers `axqlTable` reaches are, because a declaration macro's expansion is resolved where it is used. |
| `axqlMarks` | macro |  |  |  | `(names f ...)`, spread: one `?` per name. |
| `axqlFieldColumns` | macro |  |  |  | `(fields (f t) ...)`, spread: each field as its column. |
| `axqlInsert` | macro |  |  |  | An INSERT into table `t`: `*` for every column in order, or the columns the rows fill, then one `(values e ...)` per row, up to 16. |
| `axqlUpsert` | macro |  |  |  | An UPSERT into table `t`, shaped as `axqlInsert` is: a row whose rowid names a row that exists sets the columns listed and keeps the rest, and any other row is inserted. |
| `axqlCreateTable` | macro |  |  |  | A CREATE TABLE: an optional `IF NOT EXISTS`, the table's name, and one `(name TYPE ...)` per column, up to 32. |
| `axqlFieldValues` | macro |  |  |  | The typed values of a record's fields, as parameters. |
| `axqlTable` | macro |  |  |  | A table of typed rows. `(axqlTable User users (id RowId) (name String) (age OptInt))` declares, for table `users`: |

## `Axqlite.AxqlParse`

`stdlib/Axqlite/AxqlParse.ax` — 11 public names

Axqlite.AxqlParse - AXQL text to statements.

    (axqlParse "SELECT id, name FROM users WHERE id = ?1")
        ; (Ok <Parsed>): a SELECT taking one parameter
    (axqlParse "SELEC 1")
        ; (Err ...) axqSyntax "line 1, column 1: expected a statement, found \"SELEC\""
    (axqlParseScript "CREATE TABLE t (a INTEGER); INSERT INTO t VALUES (1);")
        ; (Ok <two Parsed>)

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `axqlMaxDepth` | value | `Int` |  |  | How deep parentheses and link paths may nest in one expression. The parser is recursive, so this is a stack budget: a deeper expression is a refusal rather than a crash. |
| `axqlMaxOperators` | value | `Int` |  |  | The most operators one statement may hold. Its expressions are parsed, checked and worked out by recursion, so this is a stack budget, as `axqlMaxDepth` is: a longer statement is a refusal rather than a crash, on a thread's stack as on a process's. |
| `axqlMaxParams` | value | `Int` |  |  | The most parameters a statement may take, and the largest `?N`. |
| `axqlParse` | value | `(-> String (Result Parsed Error))` | `Alloc,Mut` |  | Parse exactly one statement, with an optional `;` after it and nothing else but whitespace and comments. |
| `axqlParseScript` | value | `(-> String (Result (Vec Parsed) Error))` | `Alloc,Mut` |  | Parse a script: statements separated by `;`. Empty statements are skipped, so a script may end with `;`. |
| `axqlNameNeedsQuotes` | value | `(-> String Bool)` |  |  | Whether `name` needs double quotes to be read as a name: it isn't `[A-Za-z_][A-Za-z0-9_]*`, or it spells a reserved word. |
| `axqlKeywords` | value | `String` |  |  | The reserved words, upper case, in one string, in the order the lexer's table keeps them. `axqlIsKeyword` is the check for one. |
| `axqlContextWords` | value | `String` |  |  | The words that are keywords only where the grammar expects them, so a column may carry one as its name. |
| `axqlFunctions` | value | `String` |  |  | The functions a statement may call, by name. |
| `axqlIsKeyword` | value | `(-> String Bool)` |  |  | Whether `w`, in any case, is a reserved word. |
| `axqlTokens` | value | `(-> String (Vec Int))` | `Alloc,Mut` |  | The tokens of `src` as flat triples of start, end and class, where the class is 1 for a reserved word, 2 an identifier or quoted name, 3 a number, 4 a string or blob, 5 a parameter and 6 punctuation. The scan stops where the lexer refuses, so a text with a fault still yields its tokens up to it. For an editor that colours a statement. |

## `Axqlite.AxqlSchema`

`stdlib/Axqlite/AxqlSchema.ax` — 24 public names

Axqlite.AxqlSchema - the tables and indices a database holds.

    (axqlLoadSchema pager)                ; (Ok <Schema>): every entry
    (axqlTableDef pager schema "users")   ; (Ok <TableDef>) with its indices

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `axqlNameEq` | value | `(-> String String Bool)` |  |  | Whether two names are the same name: equal but for ASCII case. |
| `SchemaEntry` | struct |  |  |  | One row of the schema table. |
| `Schema` | struct |  |  |  | Every entry, in rowid order. |
| `IndexDef` | struct |  |  |  | An index: its name, root page, whether it's UNIQUE, and the numbers of the table columns it covers, in order. |
| `TableDef` | struct |  |  |  | A table: its name as created, root page, columns, the number of its INTEGER PRIMARY KEY column (-1 when it has none), its indices, and the tables its LINK columns point at. |
| `LinkDef` | struct |  |  |  | A LINK column: its number in the row layout, and the table it points at, whose own indices and links are left empty. |
| `kindTable` | value | `String` |  |  | The kind of a table entry. |
| `kindIndex` | value | `String` |  |  | The kind of an index entry. |
| `axqlLoadSchema` | value | `(-> Pager (Result Schema Error))` | `Alloc,IO,Mut` |  | Read every entry of the schema table. Needs a lock. |
| `axqlFindEntry` | value | `(-> Schema String (Option SchemaEntry))` | `Alloc` |  | The entry named `name`, table or index. |
| `axqlColumnIndex` | value | `(-> (Vec ColumnDef) String Int)` |  |  | The number of the column named `name`, or -1. |
| `axqlPrimaryKey` | value | `(-> (Vec ColumnDef) Int)` |  |  | The primary key column among `cols`, or -1. |
| `axqlTableNames` | value | `(-> Schema (Vec String))` | `Alloc,Mut` |  | The names of every table, in the order they were created. |
| `axqlHint` | value | `(-> String (Vec String) String String)` | `Alloc,Mut` |  | A hint naming what `name` might have meant among `names`, the kind of thing they are given by `what` ("tables", "columns"): the closest one within two edits (one, for a name of four bytes or fewer), else the list, else that there are none. |
| `axqlTableDef` | value | `(-> Schema String (Result TableDef Error))` | `Alloc,Mut` |  | The table named `name` with its indices and links, or `axqSchema`. |
| `axqlBareTableDef` | value | `(-> Schema String (Result TableDef Error))` | `Alloc,Mut` |  | The table named `name` without its indices or links: what a LINK reads. |
| `axqlLinksTo` | value | `(-> Schema String (Result (Vec String) Error))` | `Alloc,Mut` |  | Every LINK column of another table that points at table `name`, as `table.column`. |
| `axqlTableColumns` | value | `(-> String (Result (Vec ColumnDef) Error))` | `Alloc,Mut` |  | The columns a table's CREATE TABLE text declares. |
| `axqlRowRecord` | value | `(-> TableDef (Vec Value) (Result String Error))` | `Alloc,Mut` |  | The record a row of `t` is stored as: `values` in column order, with the primary key column, if any, stored as NULL. |
| `axqlRowValues` | value | `(-> TableDef String Int (Result (Vec Value) Error))` | `Alloc,Mut` |  | A row of `t` read back from its record and rowid, with the primary key column filled in. A record of the wrong width, or a value whose type its column doesn't allow, is `axqCorrupt`. |
| `axqlIndexPrefix` | value | `(-> IndexDef (Vec Value) (Result String Error))` | `Alloc,Mut` |  | The encoded values of `ix`'s columns for a row: the prefix every key for those values starts with. |
| `axqlIndexHasNull` | value | `(-> IndexDef (Vec Value) Bool)` |  |  | Whether any of `ix`'s columns is NULL in a row. Such a row never conflicts in a UNIQUE index: NULLs are distinct. |
| `axqlColumnTypes` | value | `(-> TableDef (Vec Int))` | `Alloc,Mut` |  | A table's column types, the rowid's INTEGER aside. |
| `axqlEntryRecord` | value | `(-> String String String Int String (Result String Error))` | `Alloc,Mut` |  | The record of a schema entry. |

## `Axqlite.Btree`

`stdlib/Axqlite/Btree.ax` — 17 public names

Axqlite.Btree - the one B+tree AXQLite stores tables and indices in.

        {
          (pagerBeginWrite p)?
          {
            (let root (btreeCreate p btreeTable)?)
            {
              (btreePut p root (keyRowid 1) record)?
              (pagerCommit p)
            }
          }
        }
        (btreeGet p root (keyRowid 1))  ; (Ok (Some record))
        (btreeScan p root None None true (lambda (key value) (Ok true)))

    ; every entry, in key order

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `btreeTable` | value | `Int` |  |  | The kind of a table tree, for `btreeCreate`. |
| `btreeIndex` | value | `Int` |  |  | The kind of an index tree, for `btreeCreate`. |
| `btreeMaxKey` | value | `Int` |  |  | The longest key, in bytes. |
| `btreeSchemaRoot` | value | `Int` |  |  | The root page of the schema table, the table tree every database is created with. |
| `btreeCreate` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut` |  | A new, empty tree of `kind` (`btreeTable` or `btreeIndex`); answers its root page. Inside a write transaction. |
| `btreeDrop` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut` |  | Free every page of the tree at `root`, the root included, and every overflow chain; answers how many entries it held. Inside a write transaction. The schema table's root can't be dropped. |
| `btreeClear` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut` |  | Delete every entry of the tree at `root`, keeping the root as an empty leaf; answers how many there were. Inside a write transaction. |
| `btreeGet` | value | `(-> Pager Int String (Result (Option String) Error))` | `Alloc,IO,Mut` |  | The value stored under `key`, fresh in the caller's arena, or `None`. |
| `btreePut` | value | `(-> Pager Int String String (Result Bool Error))` | `Alloc,IO,Mut` |  | Store `value` under `key`, replacing any value there. Answers true when the key is new. Inside a write transaction. |
| `btreeInsertNew` | value | `(-> Pager Int String String (Result Bool Error))` | `Alloc,IO,Mut` |  | Store `value` under `key` only when the key is new: answers false, changing nothing, when it is already there. Inside a write transaction. |
| `btreeDelete` | value | `(-> Pager Int String (Result Bool Error))` | `Alloc,IO,Mut` |  | Delete `key` and its value; answers whether it was there. Inside a write transaction. |
| `btreeScan` | value | `(-> Pager Int (Option String) (Option String) Bool (-> String String (Result Bool Error)) (Result Int Error))` | `Alloc,IO,Mut` |  | Walk the entries with `lo` <= key < `hi` (either bound `None` for no bound) in key order, or in reverse when `forward` is false, calling `f key value` on each: `Ok true` continues, `Ok false` stops, and `Err` stops and is answered. Answers how many entries `f` saw. `f` may change the tree: the scan then finds its place again after the last key it passed. |
| `btreeFirstKey` | value | `(-> Pager Int (Result (Option String) Error))` | `Alloc,IO,Mut` |  | The smallest key in the tree, or `None` when it is empty. |
| `btreeLastKey` | value | `(-> Pager Int (Result (Option String) Error))` | `Alloc,IO,Mut` |  | The largest key in the tree, or `None` when it is empty: a table's largest rowid. |
| `btreeCount` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut` |  | How many entries the tree holds, counted leaf by leaf. |
| `btreeHeight` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut` |  | The tree's height: 1 when the root is a leaf. |
| `btreeCheck` | value | `(-> Pager (Vec Int) (Result Int Error))` | `Alloc,IO,Mut,Unsafe (incomplete)` |  | Check the whole file, given the root of every tree in it (the schema root included): every page is reached exactly once, from a tree, an overflow chain or the free list; every tree's pages pass their checksums and structure checks, hold their keys in order within their parents' bounds, and have their leaves at one depth; every overflow chain holds exactly its value's bytes; and the free list is as long as the header says. Answers the pages checked, or `axqCorrupt` naming the first problem. Needs a lock. |

## `Axqlite.Pager`

`stdlib/Axqlite/Pager.ax` — 47 public names

Axqlite.Pager - one database file as numbered pages: the header,
the page cache, the file lock, the rollback journal, commit, rollback
and recovery.

    (match (pagerOpen "app.db" true false 256)
      ((Ok p)
        {
          (pagerBeginWrite p)?
          {
            (let n (pagerAlloc p)?)  ; a fresh page number
            (let page (pagerWrite p n)?)  ; its bytes, journalled first
            {
              (pagerPutBe page 0 1 5)
              (pagerCommit p)
            }
          }
        }
      )
      ((Err e) ...))

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Pager` | struct |  |  |  | An open database file. |
| `pagerPageSize` | value | `Int` |  |  | The page size in bytes. |
| `pagerUsable` | value | `Int` |  |  | The bytes of a page before its checksum; a page's content is `[0, pagerUsable)`. |
| `pagerFaultFail` | value | `Int` |  |  | The fault kinds `pagerFaultArm` takes. A failed point answers EIO and the pager carries on; a tear writes the first `arg` bytes of the write and then loses power; a power loss drops that point and every later write, sync and truncate while answering success. The strict power loss also undoes every write made since its file's last sync, as a disk that loses its whole cache would; the journal and database variants undo only that file's unsynced writes and keep the other's, as a disk that wrote the two files' caches out in either order. |
| `pagerFaultTear` | value | `Int` |  |  | The fault-injection mode that tears a page write in half, for crash tests. |
| `pagerFaultPowerLoss` | value | `Int` |  |  | The fault-injection mode that loses power after a write, for crash tests. |
| `pagerFaultPowerLossStrict` | value | `Int` |  |  | The fault-injection mode that loses power and keeps nothing not yet synced. |
| `pagerFaultPowerLossJournal` | value | `Int` |  |  | The fault-injection mode that loses power while the journal is being written. |
| `pagerFaultPowerLossDatabase` | value | `Int` |  |  | The fault-injection mode that loses power while the database file is being written. |
| `pagerChecksum` | value | `(-> Int Int Int Int)` | `Unsafe` |  | The XXH64 hash of `len` bytes at `addr` with seed `seed`, as the reference implementation computes it (words read little-endian). It is the checksum of every page and journal record. |
| `pagerGetBe` | value | `(-> Int Int Int Int)` | `Unsafe` |  | The `n` bytes (1..8) at `addr + off`, big-endian and unsigned. |
| `pagerPutBe` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` |  | Store the low `n` bytes of `v` big-endian at `addr + off`. |
| `pagerOpenFaulty` | value | `(-> String Bool Bool Int Int Int Int Bool (Result Pager Error))` | `Alloc,IO,Mut,Unsafe` |  | Open the database file at `path`, as `pagerOpen` does, with fault `kind` armed at point `at` before the first I/O, and syncs made no-ops unless `durable` (see `pagerSetDurable`): the testing entry point for crashes during recovery and creation. |
| `pagerOpen` | value | `(-> String Bool Bool Int (Result Pager Error))` | `Alloc,IO,Mut` |  | Open the database file at `path`. With `create`, a missing or empty file becomes a new database; without it, a missing file answers `axqIoFailed`. `readOnly` opens the file for reading only, and every write answers `axqReadOnly`. `cachePages` is the page cache's size in pages (at least 4). A file that isn't a database answers `axqNotADatabase`, and one that fails its header check `axqCorrupt`; while another connection holds a lock on the file, those checks wait for this connection's first lock. No lock is held when it answers. |
| `pagerClose` | value | `(-> Pager (Result Int Error))` | `Alloc,IO,Mut` |  | Close the pager: roll back an open write transaction, release every lock, close the file and free the pager. Any later use of `p` stops the program with status 85. |
| `pagerAbandon` | value | `(-> Pager Int)` | `Alloc,IO,Mut` |  | Drop the pager as a crash would: close its descriptors, which releases its lock, and free it, writing nothing. A journal it left stays hot for the next connection to recover. For tests. |
| `pagerBeginRead` | value | `(-> Pager (Result Int Error))` | `Alloc,IO,Mut` |  | Take the shared lock for reading, recovering a hot journal first. `Ok` at once when a lock is already held. `axqBusy` when a writer holds the file. |
| `pagerEndRead` | value | `(-> Pager (Result Int Error))` | `Alloc,IO,Mut` |  | Release the shared lock. Inside a write transaction it does nothing: the transaction's end releases every lock. |
| `pagerBeginWrite` | value | `(-> Pager (Result Int Error))` | `Alloc,IO,Mut` |  | Begin a write transaction: take the exclusive lock and hold it until `pagerCommit` or `pagerRollback`. From a read, the change is not atomic: when another connection gets in between, this answers `axqBusy` with no lock held at all, and the read's view is gone, so end the transaction and retry it. `axqReadOnly` on a read-only pager. `Ok` at once inside a write transaction. |
| `pagerRollback` | value | `(-> Pager (Result Int Error))` | `Alloc,IO,Mut` |  | Undo the write transaction: every page as it was at `pagerBeginWrite`. Releases every lock. `Ok` when there is no write transaction. |
| `pagerCommit` | value | `(-> Pager (Result Int Error))` | `Alloc,IO,Mut` |  | Make the write transaction durable, then release every lock. The change counter goes up by one when anything changed. On any failure the transaction is rolled back and the failure answered; the file is then exactly as it was before the transaction. |
| `pagerOpBegin` | value | `(-> Pager Int)` | `Mut` |  | Start an operation: pages fetched from now on stay cached until the next call. Answers the operation's number. |
| `pagerGet` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | The address of page `pgno`'s 4096 bytes in the cache, read and checked if it wasn't cached, and pinned until the next `pagerOpBegin`. Read only; `pagerWrite` for a page to change. Needs a lock. |
| `pagerGetTransient` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | As `pagerGet`, without pinning: the address is good only until the next pager call. |
| `pagerWrite` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | The address of page `pgno`, which the caller may now change: its original bytes are journalled first. Pinned until the next `pagerOpBegin`. Only inside a write transaction. |
| `pagerWriteTransient` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | As `pagerWrite`, without pinning: the address is good only until the next pager call. |
| `pagerAlloc` | value | `(-> Pager (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | A page for the caller to fill, zeroed: the head of the free list, or a new page at the end of the file. Answers its number. Inside a write transaction. |
| `pagerFree` | value | `(-> Pager Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Give page `pgno` back: onto the free list, or, when it is the last page of the file, off the end of the file. Inside a write transaction. Pages 0 and 1 are never freed. |
| `pagerLockLevel` | value | `(-> Pager Int)` |  |  | 0 with no lock, 1 holding the shared lock, 2 in a write transaction. |
| `pagerInWrite` | value | `(-> Pager Bool)` |  |  | Whether a write transaction is open. |
| `pagerIsReadOnly` | value | `(-> Pager Bool)` |  |  | Whether the pager was opened read-only. |
| `pagerPageCount` | value | `(-> Pager (Result Int Error))` | `Alloc` |  | How many pages the database has, header included. Needs a lock. |
| `pagerChangeCounter` | value | `(-> Pager (Result Int Error))` | `Alloc` |  | The change counter: one more after every commit that changed anything. Needs a lock. |
| `pagerSchemaVersion` | value | `(-> Pager (Result Int Error))` | `Alloc` |  | The schema version, which `pagerBumpSchemaVersion` raises. Needs a lock. |
| `pagerBumpSchemaVersion` | value | `(-> Pager (Result Int Error))` | `Alloc,IO,Mut` |  | Raise the schema version by one, answering the new version. Inside a write transaction; it commits with it. |
| `pagerMeta` | value | `(-> Pager Int (Result Int Error))` | `Alloc` |  | One of the header's eight spare words, `slot` 0..7, for the layer above (a next table id, say). Needs a lock. |
| `pagerSetMeta` | value | `(-> Pager Int Int (Result Int Error))` | `Alloc,IO,Mut` |  | Set spare header word `slot` to `v`. Inside a write transaction. |
| `pagerFreeListHead` | value | `(-> Pager (Result Int Error))` | `Alloc` |  | The first page of the free list, 0 when it is empty. Needs a lock. |
| `pagerFreeListCount` | value | `(-> Pager (Result Int Error))` | `Alloc` |  | How many pages the free list holds. Needs a lock. |
| `pagerChecked` | value | `(-> Pager Int Bool)` | `Unsafe` |  | Whether the page whose cached bytes start at `a` has had its structure checked since it was read from the file. `Btree` checks a page once per read rather than on every access. |
| `pagerSetChecked` | value | `(-> Pager Int Int)` | `Mut,Unsafe` |  | Record that the page at `a` has been checked, or was built by the caller and needs no check. |
| `pagerWriteSeq` | value | `(-> Pager Int)` |  |  | A number that changes whenever a page is written, allocated or freed: a scan compares it across a callback to learn whether the tree moved. |
| `pagerFaultArm` | value | `(-> Pager Int Int Int Int)` | `Alloc,IO,Mut` |  | Arm fault `kind` (`pagerFaultFail`, `pagerFaultTear`, `pagerFaultPowerLoss`, `pagerFaultPowerLossStrict`, `pagerFaultPowerLossJournal`, `pagerFaultPowerLossDatabase`, or 0 for none) at the `at`th write, sync or truncate from now, counting from 1. `arg` is how many bytes of a torn write land. With kind 0 the points are still counted, which is how a test learns how many a transaction has. |
| `pagerSetDurable` | value | `(-> Pager Bool Int)` | `Mut` |  | Whether syncs reach the disk. With `false` each sync is still a numbered fault point but asks nothing of the kernel: for tests that simulate their crashes with `pagerFaultArm` rather than suffer them, and would otherwise spend their time waiting on the drive. Never for data anyone keeps. |
| `pagerFaultPoints` | value | `(-> Pager Int)` |  |  | How many writes, syncs and truncates have happened since the fault was armed. |
| `pagerFaultFired` | value | `(-> Pager Bool)` |  |  | Whether the armed fault has fired. |
| `pagerStat` | value | `(-> Pager Int Int)` |  |  | A counter since the pager opened: 0 page reads from the file, 1 page writes, 2 syncs, 3 cache hits, 4 cache misses, 5 pages spilled before commit, 6 journal records written. |

## `Axqlite.Record`

`stdlib/Axqlite/Record.ax` — 13 public names

Axqlite.Record - a row's values as bytes, and keys whose byte order
is their values' order.

    (recEncode (vecPush (vecPush vecNew (VInt 7)) (VText "Ada")))
        ; (Ok <record bytes>), which `recDecode` reads back exactly
    (keyRowid 42)                      ; 8 bytes, the key of row 42
    (keyEncodeValue (VReal 2.0))       ; the same bytes as (VInt 2)
    (keyCompare a b)                   ; <0, 0 or >0, as memcmp orders

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `recEncode` | value | `(-> (Vec Value) (Result String Error))` | `Alloc,Mut,Unsafe` |  | The bytes of a row: its values in column order, as the header describes. A NaN answers `axqType`, more than 65535 columns or a record over 1 GiB `axqTooBig`. |
| `recDecode` | value | `(-> String (Result (Vec Value) Error))` | `Alloc,Mut,Unsafe` |  | The values of a record, in column order. Anything malformed answers `axqCorrupt`. |
| `recColumnCount` | value | `(-> String (Result Int Error))` | `Alloc` |  | How many columns a record holds. |
| `recColumn` | value | `(-> String Int (Result Value Error))` | `Alloc,Mut,Unsafe` |  | Column `i` of a record, without decoding the columns after it. An `i` outside the record answers `axqMisuse`. |
| `keyRowid` | value | `(-> Int String)` | `Alloc,Mut` |  | The 8-byte key of a table row: the rowid big-endian with its sign bit flipped, so bytewise order is numeric order. |
| `keyRowidOf` | value | `(-> String (Result Int Error))` | `Alloc` |  | The rowid a table key holds. |
| `keyIndexRowid` | value | `(-> String (Result Int Error))` | `Alloc` |  | The rowid in the last 8 bytes of an index key. |
| `keyWithRowid` | value | `(-> String Int String)` | `Alloc,Mut` |  | An index key: `prefix`, the key encoding of the indexed columns, then the rowid's 8 bytes. |
| `keyEncode` | value | `(-> (Vec Value) (Result String Error))` | `Alloc,Mut` |  | The key encoding of several values, one after another: the key an index on those columns stores before the rowid. A NaN answers `axqType`. |
| `keyEncodeValue` | value | `(-> Value (Result String Error))` | `Alloc,Mut` |  | The key encoding of one value. |
| `keyDecode` | value | `(-> String (Result (Vec Value) Error))` | `Alloc,Mut,Unsafe` |  | The values a key encodes. Numbers come back as `VInt` when they are integral and in the 64-bit range, and as `VReal` otherwise. Bytes that aren't a key answer `axqCorrupt`. |
| `keyPrefixEnd` | value | `(-> String (Option String))` | `Alloc,Mut,Unsafe` |  | The smallest key greater than every key that starts with `prefix`: the prefix with its last byte below FF incremented and the rest cut off. `None` when there is no such key (the prefix is empty or all FF), meaning "no upper bound". |
| `keyCompare` | value | `(-> String String Int)` |  |  | Compare two keys as the B-tree does: bytewise by unsigned value, and a prefix before any longer key. Negative, zero or positive. |

## `Axqlite.Value`

`stdlib/Axqlite/Value.ax` — 15 public names

Axqlite.Value - the values an AXQLite database holds, and the error
codes every AXQLite module answers.

    (VInt 42)            ; an INTEGER
    (VReal 2.5)          ; a REAL, IEEE 754 binary64
    (VText "Ada")        ; a TEXT, UTF-8
    (VBlob bytes)        ; a BLOB, any bytes
    VNull                ; NULL

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Value` | data |  |  |  | One value in a row, or a parameter bound to a statement. |
| `axqBusy` | value | `Int` |  |  | Another connection holds a lock this operation needs. Nothing was changed; retry later. |
| `axqCorrupt` | value | `Int` |  |  | The file isn't a consistent AXQLite database: a checksum failed, a page is malformed, or a structure points somewhere it can't. |
| `axqConstraint` | value | `Int` |  |  | A row broke a constraint: NOT NULL, a UNIQUE index, or a duplicate primary key. |
| `axqSyntax` | value | `Int` |  |  | An AXQL statement doesn't parse. The message says where. |
| `axqSchema` | value | `Int` |  |  | A statement names a table, column or index that doesn't exist, or creates one that already does. |
| `axqType` | value | `Int` |  |  | A value of the wrong type for its column, parameter or operator. |
| `axqMisuse` | value | `Int` |  |  | The API was used out of order: a wrong number of parameters, a finished transaction used again, or a statement for another connection. |
| `axqReadOnly` | value | `Int` |  |  | A write to a connection opened read-only. |
| `axqIoFailed` | value | `Int` |  |  | The operating system refused a read, write, sync or lock. The context carries its errno. |
| `axqTooBig` | value | `Int` |  |  | A value, key, row or database larger than AXQLite supports. |
| `axqNotADatabase` | value | `Int` |  |  | The file exists but isn't an AXQLite database, or was written by a format version this library doesn't read. |
| `axqArithmetic` | value | `Int` |  |  | Arithmetic in a statement overflowed 64 bits or divided by zero, or a function was given a number outside what it takes. |
| `axqNotFound` | value | `Int` |  |  | A query asked for one row and found none. |
| `axqErr` | value | `(-> Int String String (Result a Error))` | `Alloc` |  | An `Err` carrying one of the codes above, with a message and the name of the function that raised it as context. |

## `Chan`

`stdlib/Chan.ax` — 13 public names

A bounded channel of words between `parallel` bindings (R-C2,
docs/memory-model.md MM-PAR-10).

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Chan` | struct |  |  |  | A channel: one owner whose value is the ring's mapping (MM-PAR-16). |
| `chanNew` | value | `(-> Int (Result Chan Error))` | `Alloc,IO,Mut` |  | A channel of `cap` words, 1 <= cap <= 1,048,576. Answers the handle, or the mapping's error; a capacity out of range is EINVAL (22 on every target with a syscall ABI). |
| `chanSend` | value | `(-> Chan Int Bool)` | `Alloc,Block,IO,Mut` |  | Send `v`, waiting while the ring is full. `True` once it is in the ring; `False` if the channel is closed - before the call or while it waited - or poisoned (`chanPoisoned`), and then `v` was not sent. |
| `chanRecv` | value | `(-> Chan (Option Int))` | `Alloc,Block,IO,Mut` |  | Receive the oldest word, waiting while the ring is empty and open. `None` once the channel is closed AND drained - the end of the stream - or poisoned (`chanPoisoned`). |
| `chanSendTimeout` | value | `(-> Chan Int Int (Result Bool Error))` | `Alloc,Block,IO,Mut` |  | `chanSend`, waiting at most `nanos` nanoseconds - for the lock and for room. `Ok True` once `v` is in the ring; `Ok False` if the channel is closed; `Err` with code `sysTimedOut` when the time ran out first, and `Err` with code `syncOwnerDead` when the channel is poisoned - and in each of those `v` was not sent. The ring is looked at once more after the last wait, so a slot that opened as the time ran out is taken rather than refused. A non-positive `nanos` is one look, like `chanTrySend`, that says which it was. |
| `chanRecvTimeout` | value | `(-> Chan Int (Result (Option Int) Error))` | `Alloc,Block,IO,Mut` |  | `chanRecv`, waiting at most `nanos` nanoseconds - for the lock and for a word. `Ok (Some w)` the oldest word; `Ok None` the end of the stream (closed and drained); `Err` with code `sysTimedOut` when the time ran out first - the defined answer on timeout, which takes nothing out of the ring - and `Err` with code `syncOwnerDead` when the channel is poisoned. A non-positive `nanos` is one look. |
| `chanTrySend` | value | `(-> Chan Int Bool)` | `Alloc,Block,IO,Mut` |  | Send without waiting for room: `True` if `v` went into the ring, `False` if it did not because the ring is full, closed or poisoned. `chanClosed` and `chanPoisoned` tell those apart. |
| `chanTryRecv` | value | `(-> Chan (Option Int))` | `Alloc,Block,IO,Mut` |  | Receive without waiting for a word: the oldest word, or `None` when there is none right now - empty, whether or not it is closed, or poisoned; `chanClosed` and `chanPoisoned` tell them apart. |
| `chanClose` | value | `(-> Chan Int)` | `Alloc,Block,IO,Mut` |  | End the stream. Idempotent. Every waiter wakes: a sender to be refused, a receiver to drain and then see `None`. A poisoned channel has ended already, and this changes nothing. |
| `chanClosed` | value | `(-> Chan Bool)` | `Alloc,Block,IO,Mut` |  | Whether the stream has ended: closed, or poisoned. |
| `chanPoisoned` | value | `(-> Chan Bool)` |  |  | Whether a binding died holding this channel's lock, which poisoned it (the module header's "a holder that dies"). Takes no lock. |
| `chanLen` | value | `(-> Chan Int)` | `Alloc,Block,IO,Mut` |  | Words in the ring now; 0 on a poisoned channel, which yields none. |
| `chanCap` | value | `(-> Chan Int)` |  |  | How many values the channel can hold before a send blocks. |

## `Chrono`

`stdlib/Chrono.ax` — 83 public names

Chrono - dates, times of day and durations, with no time zones.

    (dateParse "2024-01-31")                  ; (Ok d)
    (dateAddMonths d 1)                       ; (Ok 2024-02-29): the day clamps
    (datetimeParse "2024-03-10T02:30:00")     ; (Ok dt)
    (datetimeFormat "%a %d %b %Y %H:%M" dt)   ; (Ok "Sun 10 Mar 2024 02:30")
    (datetimeParseUtc "2024-03-10T02:30:00+05:30")
                                              ; (Ok 2024-03-09T21:00:00)
    (durationParse "PT90M")                   ; (Ok PT1H30M)
    instantNow                                ; (Ok i), monotonic
    (sleepFor d)                              ; (Ok 0) once d has passed

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `chronoInvalidDate` | value | `Int` |  |  | A year, month and day that do not name a day: month 13, or 30 February, or 29 February in a year that is not a leap year. |
| `chronoInvalidTime` | value | `Int` |  |  | An hour, minute, second or nanosecond outside its range. |
| `chronoOutOfRange` | value | `Int` |  |  | A result outside the supported range: a date outside -9999-01-01 to 9999-12-31, a time pushed out of its day, or a duration past 2^63 - 1 nanoseconds. Every overflow answers this. |
| `chronoParseFailed` | value | `Int` |  |  | Text that is not in the format a parser reads. |
| `chronoInvalidFormat` | value | `Int` |  |  | A formatter pattern with an unknown directive or a `%` at its end. |
| `chronoClockUnavailable` | value | `Int` |  |  | This target has no realtime clock, or no monotonic one for an `Instant` or a sleep, or reading it failed. |
| `Date` | struct |  |  |  | A day in the proleptic Gregorian calendar, -9999-01-01 to 9999-12-31. Make one with `dateNew` or `dateParse`. |
| `Time` | struct |  |  |  | A time of day to the nanosecond, 00:00:00 to 23:59:59.999999999. Make one with `timeNew` or `timeParse`. |
| `NaiveDateTime` | struct |  |  |  | A date and a time of day with no time zone or offset: a wall-clock reading. Build one with `datetimeNew` or by hand, and read its parts as `dt.date` and `dt.time`. |
| `Duration` | struct |  |  |  | A signed length of time in nanoseconds, at most 2^63 - 1 either way. Make one with `durationFromSeconds` and its siblings or `durationParse`. |
| `Instant` | struct |  |  |  | A reading of the monotonic clock, in nanoseconds from an unspecified start: 0 to 2^63 - 1. Only the difference between two means anything. Make one with `instantNow` or `instantAdd`. |
| `dateIsLeapYear` | value | `(-> Int Bool)` |  |  | Whether `y` is a leap year in the proleptic Gregorian calendar: a multiple of 4, and of 400 when it is a multiple of 100. Year 0 is one, and so are -4 and -400. |
| `dateDaysInMonth` | value | `(-> Int Int Int)` |  |  | The number of days in month `m` of year `y`: 28 to 31, or 0 when `m` is outside 1 to 12. |
| `dateNew` | value | `(-> Int Int Int (Result Date Error))` | `Alloc` |  | The date `y`-`m`-`d`. A month outside 1 to 12, or a day the month does not have, answers `chronoInvalidDate`; a year outside -9999 to 9999 answers `chronoOutOfRange`. |
| `dateMin` | value | `Date` |  |  | The earliest supported date, -9999-01-01. |
| `dateMax` | value | `Date` |  |  | The latest supported date, 9999-12-31. |
| `dateYear` | value | `(-> Date Int)` |  |  | The year: -9999 to 9999, where 0 is 1 BC. |
| `dateMonth` | value | `(-> Date Int)` |  |  | The month, 1 to 12. |
| `dateDay` | value | `(-> Date Int)` |  |  | The day of the month, 1 to 31. |
| `dateWeekday` | value | `(-> Date Int)` |  |  | The ISO weekday: 1 for Monday to 7 for Sunday. |
| `dateDayOfYear` | value | `(-> Date Int)` |  |  | The day of the year: 1 for 1 January to 365, or 366 in a leap year. |
| `dateAddDays` | value | `(-> Date Int (Result Date Error))` | `Alloc` |  | `d` moved by `n` days, forward when `n` is positive. |
| `dateAddMonths` | value | `(-> Date Int (Result Date Error))` | `Alloc` |  | `d` moved by `n` calendar months. The day of the month is kept, or clamped to the new month's last day: 31 January plus one month is 28 or 29 February. |
| `dateAddYears` | value | `(-> Date Int (Result Date Error))` | `Alloc` |  | `d` moved by `n` years. 29 February becomes 28 February in a year that is not a leap year. |
| `dateDaysUntil` | value | `(-> Date Date Int)` |  |  | The number of days from `a` to `b`: positive when `b` is later. It always fits, since the whole range is under 7.4 million days. |
| `dateCompare` | value | `(-> Date Date Int)` |  |  | -1, 0 or 1 as `a` is before, the same day as, or after `b`. |
| `dateEq` | value | `(-> Date Date Bool)` |  |  | Whether `a` and `b` are the same day. |
| `timeNew` | value | `(-> Int Int Int Int (Result Time Error))` | `Alloc` |  | The time `h`:`m`:`s` and `ns` nanoseconds: hours 0 to 23, minutes and seconds 0 to 59, nanoseconds 0 to 999,999,999. Anything else answers `chronoInvalidTime`; there is no second 60. |
| `timeMidnight` | value | `Time` |  |  | Midnight, 00:00:00, the first instant of a day. |
| `timeHour` | value | `(-> Time Int)` |  |  | The hour, 0 to 23. |
| `timeMinute` | value | `(-> Time Int)` |  |  | The minute, 0 to 59. |
| `timeSecond` | value | `(-> Time Int)` |  |  | The second, 0 to 59. |
| `timeNanosecond` | value | `(-> Time Int)` |  |  | The nanoseconds past the second, 0 to 999,999,999. |
| `timeAdd` | value | `(-> Time Duration (Result Time Error))` | `Alloc` |  | `t` moved by `d`, or `chronoOutOfRange` when that leaves the day. |
| `timeAddWrapping` | value | `(-> Time Duration Time)` |  |  | `t` moved by `d` on a 24-hour clock face: 23:00 plus two hours is 01:00. The one function here that wraps. |
| `timeCompare` | value | `(-> Time Time Int)` |  |  | -1, 0 or 1 as `a` is earlier than, equal to, or later than `b`. |
| `timeEq` | value | `(-> Time Time Bool)` |  |  | Whether `a` and `b` are the same time of day. |
| `durationFromNanos` | value | `(-> Int (Result Duration Error))` | `Alloc` |  | `n` nanoseconds. Every Int but the most negative one is a duration. |
| `durationFromMicros` | value | `(-> Int (Result Duration Error))` | `Alloc` |  | `n` microseconds. |
| `durationFromMillis` | value | `(-> Int (Result Duration Error))` | `Alloc` |  | `n` milliseconds. |
| `durationFromSeconds` | value | `(-> Int (Result Duration Error))` | `Alloc` |  | `n` seconds. |
| `durationFromMinutes` | value | `(-> Int (Result Duration Error))` | `Alloc` |  | `n` minutes. |
| `durationFromHours` | value | `(-> Int (Result Duration Error))` | `Alloc` |  | `n` hours. A day is not a unit here: over a daylight-saving change it is not 24 hours long, so a program that means 24 hours says so. |
| `durationZero` | value | `Duration` |  |  | The zero duration. |
| `durationNanos` | value | `(-> Duration Int)` |  |  | The length of `d` in nanoseconds, negative for a negative duration. |
| `durationAdd` | value | `(-> Duration Duration (Result Duration Error))` | `Alloc` |  | `a + b`. |
| `durationSub` | value | `(-> Duration Duration (Result Duration Error))` | `Alloc` |  | `a - b`. |
| `durationMul` | value | `(-> Duration Int (Result Duration Error))` | `Alloc` |  | `d` times `k`. |
| `durationDiv` | value | `(-> Duration Int (Result Duration Error))` | `Alloc` |  | `d` divided by `k`, truncated toward zero. Dividing by zero answers `chronoOutOfRange`. |
| `durationNeg` | value | `(-> Duration Duration)` |  |  | `-d`. The range is the same both ways, so this always fits. |
| `durationAbs` | value | `(-> Duration Duration)` |  |  | `d` without its sign. |
| `durationCompare` | value | `(-> Duration Duration Int)` |  |  | -1, 0 or 1 as `a` is shorter than, equal to, or longer than `b`, counting sign: every negative duration is shorter than zero. |
| `durationEq` | value | `(-> Duration Duration Bool)` |  |  | Whether `a` and `b` are the same length. |
| `durationIsNegative` | value | `(-> Duration Bool)` |  |  | Whether `d` is below zero. |
| `datetimeNew` | value | `(-> Date Time NaiveDateTime)` | `Alloc` |  | The wall-clock reading `date` at `time`. |
| `datetimeAdd` | value | `(-> NaiveDateTime Duration (Result NaiveDateTime Error))` | `Alloc` |  | `dt` moved forward by `d`, or back when `d` is negative. Every day is 86,400 seconds long here. |
| `datetimeSub` | value | `(-> NaiveDateTime Duration (Result NaiveDateTime Error))` | `Alloc` |  | `dt` moved back by `d`. |
| `datetimeUntil` | value | `(-> NaiveDateTime NaiveDateTime (Result Duration Error))` | `Alloc` |  | The duration from `a` to `b`, positive when `b` is later, or `chronoOutOfRange` when they are more than 2^63 - 1 nanoseconds apart (about 292 years). |
| `datetimeCompare` | value | `(-> NaiveDateTime NaiveDateTime Int)` |  |  | -1, 0 or 1 as `a` is earlier than, equal to, or later than `b`. |
| `datetimeEq` | value | `(-> NaiveDateTime NaiveDateTime Bool)` |  |  | Whether `a` and `b` are the same reading. |
| `datetimeFromUnix` | value | `(-> Int Int (Result NaiveDateTime Error))` | `Alloc` |  | The UTC date and time of the Unix instant `secs` seconds and `nanos` nanoseconds after 1970-01-01T00:00:00Z. `secs` may be negative; `nanos` is 0 to 999,999,999, counted forward from `secs`. |
| `datetimeToUnixSeconds` | value | `(-> NaiveDateTime Int)` |  |  | The Unix seconds of `dt` read as UTC, rounded down to the second. `(timeNanosecond dt.time)` is the fraction that goes with it. |
| `datetimeNowUtc` | value | `(Result NaiveDateTime Error)` | `Alloc,IO,Mut` |  | The current UTC date and time, from the system's realtime clock (`Sys.sysNowRealtimeNanos`). That clock is the wall clock: the system may step it, so subtracting two readings does not reliably measure elapsed time. A target with no realtime clock answers `chronoClockUnavailable`. |
| `instantNow` | value | `(Result Instant Error)` | `Alloc,IO,Mut` |  | The monotonic clock now (`Sys.sysNowMonotonicNanos`). It never steps backwards, whatever happens to the time of day, so two readings measure the time between them. A target without one, such as bare metal, answers `chronoClockUnavailable`. |
| `instantUntil` | value | `(-> Instant Instant Duration)` |  |  | The time from `a` to `b`: negative when `b` is the earlier. Two instants are each 0 to 2^63 - 1, so this always fits. |
| `instantElapsed` | value | `(-> Instant (Result Duration Error))` | `Alloc,IO,Mut` |  | The time since `i`, read on the monotonic clock now. |
| `instantAdd` | value | `(-> Instant Duration (Result Instant Error))` | `Alloc` |  | `i` moved by `d`, or `chronoOutOfRange` when the result would be below 0 or past 2^63 - 1 nanoseconds. A deadline is `(instantAdd now timeout)`. |
| `instantCompare` | value | `(-> Instant Instant Int)` |  |  | -1, 0 or 1 as `a` is earlier than, the same as, or later than `b`. |
| `instantEq` | value | `(-> Instant Instant Bool)` |  |  | Whether `a` and `b` are the same reading. |
| `sleepUntil` | value | `(-> Instant (Result Int Error))` | `Alloc,Block,IO,Mut` |  | Block until the monotonic clock reaches `i`: `Ok 0` once it has, and at once for an instant already past. A wake that comes early sleeps again, so the sleep never ends short. A target without a monotonic clock answers `chronoClockUnavailable`. |
| `sleepFor` | value | `(-> Duration (Result Int Error))` | `Alloc,Block,IO,Mut` |  | Block for at least `d`, measured on the monotonic clock: `Ok 0` once it has passed. Zero or a negative duration answers at once, and a duration past the clock's range sleeps until its end. A target without a monotonic clock answers `chronoClockUnavailable`. |
| `dateToString` | value | `(-> Date String)` | `Alloc,Mut` |  | `d` in ISO 8601 extended format: `2024-02-29`, or `-000044-03-15` for a year outside 0 to 9999. |
| `timeToString` | value | `(-> Time String)` | `Alloc,Mut` |  | `t` as `HH:MM:SS`, with a fraction only when it is not zero and without trailing zeros: `14:05:09`, `14:05:09.5`. |
| `datetimeToString` | value | `(-> NaiveDateTime String)` | `Alloc,Mut` |  | `dt` as its date, `T` and its time: `2024-02-29T14:05:09.5`. |
| `durationToString` | value | `(-> Duration String)` | `Alloc,Mut` |  | `d` in ISO 8601 as hours, minutes and seconds, largest unit hours: `PT1H30M`, `PT0.5S`, `-PT36H`, and `PT0S` for zero. A unit that is zero is left out. |
| `dateParse` | value | `(-> String (Result Date Error))` | `Alloc` |  | The date spelled by all of `s`: `YYYY-MM-DD` for years 0000 to 9999, and a sign and six year digits for any year, as in `-000044-03-15` (year -44, which is 45 BC). `-000000` is refused. A month or day the calendar does not have answers `chronoInvalidDate`, a year outside -9999 to 9999 `chronoOutOfRange`, and anything else `chronoParseFailed`. |
| `timeParse` | value | `(-> String (Result Time Error))` | `Alloc` |  | The time spelled by all of `s`: `HH:MM`, `HH:MM:SS`, or `HH:MM:SS` with `.` or `,` and one to nine fraction digits. A leap second `:60` reads as `:59`; `24:00` is refused. A field out of range answers `chronoInvalidTime`, anything else `chronoParseFailed`. |
| `datetimeParse` | value | `(-> String (Result NaiveDateTime Error))` | `Alloc` |  | The date and time spelled by all of `s`: a date as `dateParse` reads one, `T` (or `t`, or one space, as RFC 3339 permits), and a time as `timeParse` reads one. A trailing `Z` or offset is refused, because a naive datetime has none; `datetimeParseUtc` reads timestamps that do. |
| `datetimeParseUtc` | value | `(-> String (Result NaiveDateTime Error))` | `Alloc` |  | The UTC date and time of an RFC 3339 timestamp, which must end in `Z` or an offset `+HH:MM` or `-HH:MM`: `2024-03-10T02:30:00+05:30` is 2024-03-09T21:00:00. The offset is subtracted, which may move the date. This reads a fixed offset; it knows nothing of time zones. |
| `durationParse` | value | `(-> String (Result Duration Error))` | `Alloc` |  | The duration spelled by all of `s`: `PT`, then hours `H`, minutes `M` and seconds `S`, each optional but in that order and at least one of them, with a fraction of one to nine digits on the seconds only. A leading `-` makes it negative: `PT1H30M`, `PT0.5S`, `-PT36H`. Days, weeks, months and years are refused, because none is a fixed length. |
| `datetimeFormat` | value | `(-> String NaiveDateTime (Result String Error))` | `Alloc,Mut` |  | `dt` written out by `pattern`, whose `%` directives are replaced and whose other bytes are copied. The whole pattern is checked before anything is written: an unknown directive or a `%` at the end answers `chronoInvalidFormat`. |
| `dateFormat` | value | `(-> String Date (Result String Error))` | `Alloc,Mut` |  | `d` written out by `pattern`, as `datetimeFormat` does. A time directive, such as `%H`, answers `chronoInvalidFormat`. |
| `timeFormat` | value | `(-> String Time (Result String Error))` | `Alloc,Mut` |  | `t` written out by `pattern`, as `datetimeFormat` does. A date directive, such as `%Y`, answers `chronoInvalidFormat`. |

## `Crypto.Aead`

`stdlib/Crypto/Aead.ax` — 11 public names

Crypto.Aead - nonces for authenticated encryption, and a sequence
that never hands out the same one twice.

    {
      (let key (unwrapOr (aes256GcmKeyGenerate) ...))
      (let seq (unwrapOr (nonceSequenceNew "srv1") ...))
      (match (nonceSequenceNext seq)
        ((Ok nonce)
          {
            (saveCounter (nonceSequencePosition seq))  ; persist first
            (aes256GcmSeal key nonce aad message)  ; then seal
          }
        )
        ((Err e) (Err e)))
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `AeadNonce` | struct |  |  |  | A 12-byte nonce for one AEAD message. Build it with `aeadNonceFromBytes`, `aeadNonceRandom` or `nonceSequenceNext`; the AEADs refuse one of any other length. |
| `aeadNonceLen` | value | `Int` |  |  | The nonce length the AEADs take: 12 bytes. |
| `aeadTagLen` | value | `Int` |  |  | The tag every seal appends and every open checks: 16 bytes. Shorter tags are not offered. |
| `aeadNonceFromBytes` | value | `(-> String (Result AeadNonce Error))` | `Alloc,Mut` |  | A nonce holding a copy of `b`, which must be exactly 12 bytes. Anything else answers `cryptoInvalidLength`: other nonce lengths exist in GCM, and this suite does not take them. |
| `aeadNonceBytes` | value | `(-> AeadNonce String)` |  |  | The nonce's 12 bytes, to send beside the ciphertext. |
| `aeadNonceRandom` | value | `(Result AeadNonce Error)` | `Alloc,Entropy,IO,Mut` |  | A nonce of 12 bytes from the kernel's entropy source. Use at most 2^32 random nonces under one key (SP 800-38D 8.3); the module header says why. |
| `NonceSequence` | struct |  |  |  | A source of nonces that never repeats: a fixed 4-byte prefix and a 64-bit big-endian counter, the prefix and invocation fields of SP 800-38D 8.2.1. The state is the next nonce itself, 12 bytes. The counter runs from 0 to 2^63 - 2, and one sequence is not safe to use from two threads at once. |
| `nonceSequenceNew` | value | `(-> String (Result NonceSequence Error))` | `Alloc,Mut` |  | A sequence whose first nonce is `prefix` followed by a zero counter. `prefix` must be 4 bytes, and distinct for every sender that shares the key. |
| `nonceSequenceResume` | value | `(-> String Int (Result NonceSequence Error))` | `Alloc,Mut` |  | A sequence that carries on from `position`, a value read back from `nonceSequencePosition` and persisted before the nonce it followed was used. `position` is 0 to 2^63 - 1; at 2^63 - 1 the sequence is already used up. |
| `nonceSequenceNext` | value | `(-> NonceSequence (Result AeadNonce Error))` | `Alloc,Mut` |  | The next nonce, and the counter moved on past it. Once the counter reaches 2^63 - 1 every call answers `cryptoLimitExceeded`: the sequence never wraps round to a nonce it has given out. A state that is not 12 bytes answers `cryptoInvalidLength`. |
| `nonceSequencePosition` | value | `(-> NonceSequence Int)` |  |  | The counter the next nonce will carry: the value to persist, before sealing, so a restart can resume after every nonce already given out. -1 for a state that is not 12 bytes. |

## `Crypto.Aes`

`stdlib/Crypto/Aes.ax` — 9 public names

Crypto.Aes - the AES block cipher (FIPS 197), all three key sizes,
as a constant-time bitsliced kernel. Hazardous layer.

    {
      (let sched (strAlloc (aesScheduleBytes 32)))
      (let work (strAlloc aesKeyWorkBytes))
      (let q (strAlloc aesStateBytes))
      {
        (aesKeyExpand (strData sched) (strData key) 32 (strData work))
        (aesEncryptBlocks (strData sched) 14 (strData pt) (strData ct) 1 (strData q))
        (ctWipe (strData sched) (aesScheduleBytes 32))
        (ctWipe (strData q) aesStateBytes)
      }
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `aesRounds` | value | `(-> Int Int)` |  |  | The number of rounds for a key of `keyLen` bytes: 10, 12 or 14 for 16, 24 or 32, and 0 for any other length. |
| `aesScheduleBytes` | value | `(-> Int Int)` |  |  | The bytes an expanded schedule for a key of `keyLen` bytes occupies: eight words per round key, 704, 832 or 960. 0 for a bad length. |
| `aesKeyWorkBytes` | value | `Int` |  |  | The scratch `aesKeyExpand` needs: the 60-word FIPS 197 schedule and an 8-word state. |
| `aesStateBytes` | value | `Int` |  |  | The bitsliced state: eight words, four blocks. |
| `aesCtrWorkBytes` | value | `Int` |  |  | The scratch `aesCtr32Xor` needs: the state and one 64-byte run of keystream. |
| `aesKeyExpand` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` |  | Expand the `keyLen`-byte key at `key` into the bitsliced schedule at `out`, `aesScheduleBytes keyLen` bytes. Answers the number of rounds, or 0, writing nothing, when `keyLen` is not 16, 24 or 32. The scratch at `work` is wiped before this returns. |
| `aesEncryptBlocks` | value | `(-> Int Int Int Int Int Int Int)` | `Mut` |  | Encrypt `n` 16-byte blocks from `src` to `dst`, each on its own (the raw cipher, FIPS 197 5.1; ECB when read as a mode). `src` and `dst` may be the same address. `q` is scratch the caller wipes. |
| `aesDecryptBlocks` | value | `(-> Int Int Int Int Int Int Int)` | `Mut` |  | Decrypt `n` 16-byte blocks from `src` to `dst` (FIPS 197 5.3). |
| `aesCtr32Xor` | value | `(-> Int Int Int Int Int Int Int Int Int)` | `Mut,Unsafe` |  | XOR `len` bytes from `src` with the keystream E(iv \|\| ctr), E(iv \|\| ctr + 1), ... into `dst`, where `iv` is 12 bytes and the counter is the last 4 bytes of each block, big-endian, incremented modulo 2^32. Answers the counter after the last block used. `src` and `dst` may be the same address. `work` holds keystream when this returns; the caller wipes it. |

## `Crypto.AesGcm`

`stdlib/Crypto/AesGcm.ax` — 14 public names

Crypto.AesGcm - AES-128-GCM and AES-256-GCM authenticated
encryption (SP 800-38D), one message at a time.

    {
      (let key (unwrapOr (aes256GcmKeyGenerate) ...))
      (let nonce (unwrapOr (aeadNonceRandom) ...))
      (match (aes256GcmSeal key nonce "header" "attack at dawn")
        ((Ok sealed)
          ; ciphertext || 16-byte tag
          (aes256GcmOpen key nonce "header" sealed)
        )
        ; (Ok "attack at dawn")
        ((Err e) (Err e)))
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Aes128GcmKey` | struct |  |  |  | An AES-128-GCM key: 16 bytes, with its schedule and hash key, in the secret store (kind 19). |
| `Aes256GcmKey` | struct |  |  |  | An AES-256-GCM key: 32 bytes, with its schedule and hash key, in the secret store (kind 20). |
| `aes128GcmKeyGenerate` | value | `(Result Aes128GcmKey Error)` | `Alloc,Entropy,IO,Mut` |  | A fresh random AES-128-GCM key from the kernel's entropy source. |
| `aes256GcmKeyGenerate` | value | `(Result Aes256GcmKey Error)` | `Alloc,Entropy,IO,Mut` |  | A fresh random AES-256-GCM key from the kernel's entropy source. |
| `aes128GcmKeyFromSecret` | value | `(-> SecretBytes (Result Aes128GcmKey Error))` | `Alloc,IO,Mut` |  | An AES-128-GCM key holding a copy of `s`, which must be 16 bytes. This is also the deterministic way to make a key, for known-answer tests and protocols that derive one; `s` is left as it was. |
| `aes256GcmKeyFromSecret` | value | `(-> SecretBytes (Result Aes256GcmKey Error))` | `Alloc,IO,Mut` |  | An AES-256-GCM key holding a copy of `s`, which must be 32 bytes. |
| `aes128GcmKeyExport` | value | `(-> Aes128GcmKey (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | The key's 16 bytes as a new `SecretBytes`, for storing it somewhere you trust. The key itself stays live. |
| `aes256GcmKeyExport` | value | `(-> Aes256GcmKey (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | The key's 32 bytes as a new `SecretBytes`. |
| `aes128GcmKeyWipe` | value | `(-> Aes128GcmKey Int)` | `Alloc,IO,Mut` |  | Erase the key, its schedule and its hash key, and free the store. Any later use of `k` stops the program with status 85. Answers 0. |
| `aes256GcmKeyWipe` | value | `(-> Aes256GcmKey Int)` | `Alloc,IO,Mut` |  | Erase an AES-256-GCM key and free the store. Answers 0. |
| `aes128GcmSeal` | value | `(-> Aes128GcmKey AeadNonce String String (Result String Error))` | `Alloc,Mut` |  | Encrypt and authenticate `plaintext` with `aad` under `key` and `nonce`: the ciphertext, the same length as the plaintext, followed by the 16-byte tag. The nonce must never have been used with this key before. |
| `aes128GcmOpen` | value | `(-> Aes128GcmKey AeadNonce String String (Result String Error))` | `Alloc,Mut` |  | Check and decrypt `sealed` (ciphertext \|\| tag) with `aad` under `key` and `nonce`: the plaintext, or `cryptoAuthFailed` for any failure. Nothing is decrypted unless the tag matches. |
| `aes256GcmSeal` | value | `(-> Aes256GcmKey AeadNonce String String (Result String Error))` | `Alloc,Mut` |  | Encrypt and authenticate with AES-256-GCM: ciphertext \|\| 16-byte tag. |
| `aes256GcmOpen` | value | `(-> Aes256GcmKey AeadNonce String String (Result String Error))` | `Alloc,Mut` |  | Check and decrypt an AES-256-GCM message: the plaintext, or `cryptoAuthFailed` for any failure. |

## `Crypto.Blake2b`

`stdlib/Crypto/Blake2b.ax` — 14 public names

Crypto.Blake2b - BLAKE2b, unkeyed and keyed.

    (hexEncode (blake2b512 "abc"))
    ; "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1
    ;  7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"

    (blake2b 32 key msg)             ; (Ok <32-byte keyed digest>)

    (match (blake2bNew 64)           ; streaming
      ((Ok h) { (blake2bUpdate h "a") (blake2bUpdate h "bc") (blake2bFinal h) })
      ((Err e) ""))

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `blake2bCompress` | value | `(-> Int Int Int Bool Int)` | `Mut` |  | Fold one 128-byte block at `p` into the chaining value in words 0-7 at `st`, after advancing the byte counter in words 8 and 9 by `inc`; `last` sets the final-block flag. This is F of RFC 7693 section 3.2 with its counter bookkeeping, for a caller building its own mode over BLAKE2b. Answers 0. |
| `blake2bAddr` | value | `(-> Int Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` |  | The BLAKE2b digest of `n` bytes at `p`, `outLen` bytes long and keyed with the `keyLen` bytes at `key`, written to `out`. The scratch state is erased before it returns. Answers 0. |
| `blake2b` | value | `(-> Int String String (Result String Error))` | `Alloc,Mut` |  | The `outLen`-byte BLAKE2b digest of `msg` keyed with `key`; an empty key is unkeyed BLAKE2b. A digest length outside 1 to 64 or a key over 64 bytes answers `cryptoInvalidLength`. |
| `blake2b512` | value | `(-> String String)` | `Alloc,Mut` |  | The 64-byte unkeyed BLAKE2b digest of `msg` (BLAKE2b-512). |
| `blake2b256` | value | `(-> String String)` | `Alloc,Mut` |  | The 32-byte unkeyed BLAKE2b digest of `msg` (BLAKE2b-256). |
| `Blake2b` | struct |  |  |  | A BLAKE2b hash in progress. Make one with `blake2bNew` or `blake2bNewKeyed`. |
| `blake2bNew` | value | `(-> Int (Result Blake2b Error))` | `Alloc,Mut` |  | A fresh unkeyed hash with an `outLen`-byte digest, or `cryptoInvalidLength` when `outLen` is outside 1 to 64. |
| `blake2bNewKeyed` | value | `(-> Int String (Result Blake2b Error))` | `Alloc,Mut` |  | A fresh hash with an `outLen`-byte digest keyed with `key`, or `cryptoInvalidLength` when `outLen` is outside 1 to 64 or `key` is over 64 bytes. The state keeps a copy of the key until it is wiped. |
| `blake2bNewKeyedSecret` | value | `(-> Int SecretBytes (Result Blake2b Error))` | `Alloc,Mut` |  | `blake2bNewKeyed` with a key held in the secret store. |
| `blake2bUpdateAddr` | value | `(-> Blake2b Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`. Answers 0, or -1 when `h` is not a live BLAKE2b state or `n` is negative, and then absorbs nothing. |
| `blake2bUpdate` | value | `(-> Blake2b String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `h` is not a live BLAKE2b state. |
| `blake2bFinal` | value | `(-> Blake2b String)` | `Alloc,Mut,Unsafe` |  | The digest of everything absorbed, as long as `h` was made to give. `h` is then reset to a fresh hash with the same digest length and key. A value that is not a live BLAKE2b state answers the empty string. |
| `blake2bCopy` | value | `(-> Blake2b Blake2b)` | `Alloc,Mut` |  | An independent copy of `h`, which goes on from the same point. It holds its own copy of any key. |
| `blake2bWipe` | value | `(-> Blake2b Int)` | `Mut,Unsafe` |  | Erase everything `h` holds, the key included. Every later operation on it is refused. Answers 0, or -1 with nothing written when `h` is not a BLAKE2b state. |

## `Crypto.Bytes`

`stdlib/Crypto/Bytes.ax` — 16 public names

Crypto.Bytes - byte strings as the Crypto modules pass them around.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `bytesNew` | value | `(-> Int String)` | `Alloc,Mut` |  | `n` zero bytes, as a fresh string a caller may write into through `strData` before handing it on. |
| `bytesFromAddr` | value | `(-> Int Int String)` | `Alloc,Mut` |  | A fresh copy of `n` bytes at `p`. |
| `bytesU32Be` | value | `(-> Int String)` | `Alloc,Mut` |  | The 4 bytes of `v`'s low 32 bits, most significant first. |
| `bytesU32Le` | value | `(-> Int String)` | `Alloc,Mut` |  | The 4 bytes of `v`'s low 32 bits, least significant first. |
| `bytesU64Be` | value | `(-> Int String)` | `Alloc,Mut` |  | The 8 bytes of `v`, most significant first. |
| `bytesU64Le` | value | `(-> Int String)` | `Alloc,Mut` |  | The 8 bytes of `v`, least significant first. |
| `bytesXor` | value | `(-> String String (Result String Error))` | `Alloc,Mut,Unsafe` |  | The byte-wise XOR of two strings of the same length, or `Err` when the lengths differ. |
| `bytesEqCt` | value | `(-> String String Bool)` | `Mut` |  | Whether `a` and `b` hold the same bytes, in time that depends only on their lengths. Lengths are public here: two strings of different lengths answer false at once. Use this, never `==` or `strEq`, to compare a tag, a digest of a secret, or anything else an attacker could learn from how long a comparison took. |
| `hexEncode` | value | `(-> String String)` | `Alloc,Mut,Unsafe` |  | `s`'s bytes as lower-case hex, two digits a byte. |
| `hexDecode` | value | `(-> String (Result String Error))` | `Alloc,Mut,Unsafe` |  | The bytes a hex string spells, or `Err` when its length is odd or any character is not a hex digit. Upper- and lower-case both decode. |
| `b64Encode` | value | `(-> String String)` | `Alloc,Mut` |  | Standard base64 with '=' padding, as RFC 4648 section 4 writes it. |
| `b64EncodeNoPad` | value | `(-> String String)` | `Alloc,Mut` |  | Standard base64 without padding: the spelling of the PHC string format that password records use. |
| `b64UrlEncode` | value | `(-> String String)` | `Alloc,Mut` |  | URL-safe base64 without padding (RFC 4648 section 5), for tokens that go in a URL or a file name. |
| `b64Decode` | value | `(-> String (Result String Error))` | `Alloc,Mut` |  | Decode padded standard base64. The length must be a multiple of four and the padding exactly what the length calls for. |
| `b64DecodeNoPad` | value | `(-> String (Result String Error))` | `Alloc,Mut` |  | Decode standard base64 that carries no padding. An '=' anywhere is refused. |
| `b64UrlDecode` | value | `(-> String (Result String Error))` | `Alloc,Mut` |  | Decode URL-safe base64 without padding. |

## `Crypto.ChaCha20`

`stdlib/Crypto/ChaCha20.ax` — 3 public names

Crypto.ChaCha20 - the ChaCha20 stream cipher of RFC 8439, with a
256-bit key, a 96-bit nonce and a 32-bit block counter. Hazardous
layer.

      {
        (let block (strAlloc chacha20BlockBytes))
        (chacha20Block (strData block) keyAddr 1 (strData nonce))
      }
    ; block holds keystream block 1 for that key and nonce

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `chacha20BlockBytes` | value | `Int` |  |  | The bytes `chacha20Block` writes through: 64 of keystream, then 64 of scratch it wipes. |
| `chacha20Block` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` |  | Write keystream block `counter` for the 32-byte key at `key` and the 12-byte nonce at `nonce` to the first 64 bytes at `out` (RFC 8439 2.3): the state after 20 rounds, ten column rounds alternating with ten diagonal rounds, added word by word to the state it started from. `out` also holds the working state, so it names `chacha20BlockBytes`; the second 64 bytes are wiped before this returns. `counter` is taken modulo 2^32. |
| `chacha20Xor` | value | `(-> Int Int Int Int Int Int Int Int)` | `Mut,Unsafe` |  | XOR `len` bytes from `src` with the keystream starting at block `counter` into `dst` (RFC 8439 2.4). `src` and `dst` may be the same address. `work` is `chacha20BlockBytes` of scratch; its first 64 bytes hold the last keystream block when this returns, and the caller wipes them. Answers the counter after the last block used. The caller keeps `counter` plus the number of blocks within 2^32. |

## `Crypto.ChaCha20Poly1305`

`stdlib/Crypto/ChaCha20Poly1305.ax` — 7 public names

Crypto.ChaCha20Poly1305 - the ChaCha20-Poly1305 AEAD of RFC 8439,
one message at a time.

    {
      (let key (unwrapOr (chacha20Poly1305KeyGenerate) ...))
      (let nonce (unwrapOr (aeadNonceRandom) ...))
      (match (chacha20Poly1305Seal key nonce "header" "attack at dawn")
        ((Ok sealed)
          ; ciphertext || 16-byte tag
          (chacha20Poly1305Open key nonce "header" sealed)
        )
        ; (Ok "attack at dawn")
        ((Err e) (Err e)))
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `ChaCha20Poly1305Key` | struct |  |  |  | A ChaCha20-Poly1305 key: 32 bytes in the secret store (kind 21). |
| `chacha20Poly1305KeyGenerate` | value | `(Result ChaCha20Poly1305Key Error)` | `Alloc,Entropy,IO,Mut` |  | A fresh random ChaCha20-Poly1305 key from the kernel's entropy source, drawn straight into the secret store. |
| `chacha20Poly1305KeyFromSecret` | value | `(-> SecretBytes (Result ChaCha20Poly1305Key Error))` | `Alloc,IO,Mut` |  | A key holding a copy of `s`, which must be 32 bytes. This is also the deterministic way to make a key, for known-answer tests and protocols that derive one; `s` is left as it was. |
| `chacha20Poly1305KeyExport` | value | `(-> ChaCha20Poly1305Key (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | The key's 32 bytes as a new `SecretBytes`, for storing it somewhere you trust. The key itself stays live. |
| `chacha20Poly1305KeyWipe` | value | `(-> ChaCha20Poly1305Key Int)` | `Alloc,IO,Mut` |  | Erase the key and free the store. Any later use of `k` stops the program with status 85. Answers 0. |
| `chacha20Poly1305Seal` | value | `(-> ChaCha20Poly1305Key AeadNonce String String (Result String Error))` | `Alloc,Mut` |  | Encrypt and authenticate `plaintext` with `aad` under `key` and `nonce`: the ciphertext, the same length as the plaintext, followed by the 16-byte tag. The nonce must never have been used with this key before. A nonce that is not 12 bytes answers `cryptoInvalidLength`, and a plaintext over the limit `cryptoLimitExceeded`. |
| `chacha20Poly1305Open` | value | `(-> ChaCha20Poly1305Key AeadNonce String String (Result String Error))` | `Alloc,Mut` |  | Check and decrypt `sealed` (ciphertext \|\| tag) with `aad` under `key` and `nonce`: the plaintext, or `cryptoAuthFailed` for any failure. Nothing is decrypted unless the tag matches. |

## `Crypto.Ct`

`stdlib/Crypto/Ct.ax` — 27 public names

Crypto.Ct - the constant-time building blocks every Crypto module
shares.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `ctBarrier` | value | `(-> Int Int)` | `Mut,Unsafe` |  | `x`, unchanged, through an empty assembly block: the optimiser has to treat the answer as any word at all. This is what stops a mask from being reasoned back into a branch. |
| `ctMaskNz` | value | `(-> Int Int)` | `Mut` |  | -1 when `x` is not zero, 0 when it is. For any nonzero `x`, one of `x` and `-x` has the sign bit set (for the most negative word both do), so an arithmetic shift of their `\|` spreads it. |
| `ctMaskZero` | value | `(-> Int Int)` | `Mut` |  | -1 when `x` is zero, 0 when it is not. |
| `ctMaskEq` | value | `(-> Int Int Int)` | `Mut` |  | -1 when `a` equals `b`, 0 otherwise. |
| `ctMaskLtU` | value | `(-> Int Int Int)` | `Mut` |  | -1 when `a` is below `b` as UNSIGNED 64-bit words, 0 otherwise. This is the borrow out of `a - b`, computed from the operands' top bits (Hacker's Delight 2-13), so it is right across the whole range where the signed `(- a b)` would overflow. |
| `ctMaskNeg` | value | `(-> Int Int)` | `Mut` |  | -1 when `x` is negative, 0 otherwise. |
| `ctSelect` | value | `(-> Int Int Int Int)` |  |  | `a` where `m` is -1, `b` where `m` is 0. `m` must be a mask. |
| `ctMaskFromBit` | value | `(-> Int Int)` | `Mut` |  | A mask from a 0/1 bit: 1 becomes -1 and 0 stays 0. |
| `shrU` | value | `(-> Int Int Int)` |  |  | `x` shifted right by `n` bits with zeros in, for 1 <= n <= 63. |
| `rotl64` | value | `(-> Int Int Int)` |  |  | A 64-bit rotation left by `n`, for 1 <= n <= 63. |
| `rotr64` | value | `(-> Int Int Int)` |  |  | A 64-bit rotation right by `n`, for 1 <= n <= 63. |
| `mask32` | value | `Int` |  |  | The 32-bit words a SHA-256 or ChaCha20 state holds live in the low half of an Int with the high half zero, so `>>` on one is already logical. Every operation that can carry into the high half masks back to 32 bits. |
| `rotl32` | value | `(-> Int Int Int)` |  |  | A 32-bit rotation left by `n`, for 1 <= n <= 31, of a word in 0..2^32-1. The answer is in the same range. |
| `rotr32` | value | `(-> Int Int Int)` |  |  | A 32-bit rotation right by `n`, for 1 <= n <= 31. |
| `add32` | value | `(-> Int Int Int)` |  |  | `a + b` modulo 2^32, for words in 0..2^32-1. |
| `ld32le` | value | `(-> Int Int Int)` | `Unsafe` |  | The 32-bit little-endian word at byte `off` of the block at `p`, read in constant time. |
| `ld32be` | value | `(-> Int Int Int)` | `Unsafe` |  | The 32-bit big-endian word at byte `off` of the block at `p`, read in constant time. |
| `ld64le` | value | `(-> Int Int Int)` |  |  | The 64-bit little-endian word at byte `off` of the block at `p`, read in constant time. |
| `ld64be` | value | `(-> Int Int Int)` |  |  | The 64-bit big-endian word at byte `off` of the block at `p`, read in constant time. |
| `st32le` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | Store the low 32 bits of `v` little-endian at byte `off` of the block at `p`, in constant time. Answers 0. |
| `st32be` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | Store the low 32 bits of `v` big-endian at byte `off` of the block at `p`, in constant time. Answers 0. |
| `st64le` | value | `(-> Int Int Int Int)` | `Mut` |  | Store `v` little-endian at byte `off` of the block at `p`, in constant time. Answers 0. |
| `st64be` | value | `(-> Int Int Int Int)` | `Mut` |  | Store `v` big-endian at byte `off` of the block at `p`, in constant time. Answers 0. |
| `ctEqAddr` | value | `(-> Int Int Int Bool)` | `Mut,Unsafe` |  | Whether `n` bytes at `a` and at `b` are equal, taking the same time whichever bytes differ. `n` is public; the contents are not. The running difference passes through the barrier once per byte, so the loop cannot be rewritten to stop at the first difference. |
| `ctWipe` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | Overwrite `n` bytes at `p` with zeros, in a way the optimiser may not delete. Answers 0. |
| `ctCopy` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | Copy `n` bytes from `src` to `dst`, which must not overlap. The same loop as `rawCopy`; here so a Crypto module needs one import for its memory work. |
| `ctSwapWords` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` |  | Conditionally swap `n` words at `a` and `b`: swapped where `m` is -1, left alone where `m` is 0. The Montgomery ladder's step, and any other choice between two buffers a secret makes. |

## `Crypto.Curve25519`

`stdlib/Crypto/Curve25519.ax` — 23 public names

Crypto.Curve25519 - the Ed25519 group: points of the twisted Edwards
curve -x^2 + y^2 = 1 + d x^2 y^2 over GF(2^255 - 19), their
arithmetic and their 32-byte encoding.

    {
      (let h (rawAlloc ge25519P3Bytes))
      (let enc (strAlloc 32))
      {
        (ge25519ScalarMultBase h (strData scalar))  ; h = [scalar]B
        (ge25519ToBytes (strData enc) h)  ; RFC 8032 encoding
        (ge25519FromBytesVartime h (strData enc))  ; 0: decoded again
      }
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `ge25519P2Bytes` | value | `Int` |  |  | Bytes in a P2 point (X:Y:Z). |
| `ge25519P3Bytes` | value | `Int` |  |  | Bytes in a P3 point (X:Y:Z:T). |
| `ge25519P1P1Bytes` | value | `Int` |  |  | Bytes in a P1P1 point, the output of an addition or doubling. |
| `ge25519PrecompBytes` | value | `Int` |  |  | Bytes in a Precomp point (y+x, y-x, 2dxy). |
| `ge25519CachedBytes` | value | `Int` |  |  | Bytes in a Cached point (Y+X, Y-X, Z, 2dT). |
| `ge25519D` | value | `(-> Int Int)` | `Mut` |  | The curve constant d = -121665/121666 (ref10's d.h). |
| `ge25519D2` | value | `(-> Int Int)` | `Mut` |  | 2d (ref10's d2.h). |
| `ge25519Base` | value | `(-> Int Int)` | `Mut` |  | The base point B = (x, 4/5) with x even (RFC 8032, section 5.1), as a P3 at `h`. |
| `ge25519P3Zero` | value | `(-> Int Int)` | `Mut` |  | The neutral element (0, 1) as a P3. |
| `ge25519P2Zero` | value | `(-> Int Int)` | `Mut` |  | The neutral element as a P2. |
| `ge25519P1P1ToP2` | value | `(-> Int Int Int)` | `Mut` |  | r = p as a P2 (ge_p1p1_to_p2). |
| `ge25519P1P1ToP3` | value | `(-> Int Int Int)` | `Mut` |  | r = p as a P3 (ge_p1p1_to_p3). |
| `ge25519P3ToCached` | value | `(-> Int Int Int Int)` | `Mut` |  | r = p as a Cached point (ge_p3_to_cached). `t` is one field element of scratch. |
| `ge25519P2Dbl` | value | `(-> Int Int Int Int)` | `Mut` |  | r = 2p, for a P2 (or a P3's first three coordinates) at `p` (ge_p2_dbl.h). `t` is one field element of scratch. |
| `ge25519Add` | value | `(-> Int Int Int Int Int)` | `Mut` |  | r = p + q, for a P3 `p` and a Cached `q` (ge_add.h). `t` is one field element of scratch. |
| `ge25519Sub` | value | `(-> Int Int Int Int Int)` | `Mut` |  | r = p - q, for a P3 `p` and a Cached `q` (ge_sub.h). |
| `ge25519Madd` | value | `(-> Int Int Int Int Int)` | `Mut` |  | r = p + q, for a P3 `p` and a Precomp `q` (ge_madd.h). |
| `ge25519ToBytes` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` |  | Write the 32-byte encoding of the P2 (or P3) at `h` at `s`: y, with the low bit of x in bit 255 (ge_tobytes.c). |
| `ge25519FromBytesVartime` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` |  | Decode the 32 bytes at `s` into the P3 at `h`, strictly (RFC 8032, section 5.1.3): answers 0, or -1 when y is not below p, when no x satisfies the curve equation, or when x is 0 and the sign bit is set, and `h` is then unspecified. Variable time: for public keys and signatures only. Points of small order decode; nothing here asks what order a point has. |
| `ge25519P3Neg` | value | `(-> Int Int)` | `Mut` |  | h = -h, for a P3. |
| `ge25519CombTable` | value | `(-> Int Int)` | `Mut` |  | The two combs as sixteen Precomp points at `t`: entry j of the low comb (0 <= j < 8) is 2^96 B + sum over k < 3 of (+/-) 2^(32k) B, the sign of 2^(32k) B being bit k of j; the high comb, entries 8 to 15, is 2^128 times the low. These are Monocypher's b_comb_low and b_comb_high; tests/crypto/302-curve25519-group.ax recomputes them. |
| `ge25519ScalarMultBase` | value | `(-> Int Int Int)` | `Alloc,Mut,Unsafe` |  | h = [a]B for the 32-byte scalar at `a`, any value below 2^256, in time that does not depend on `a`. |
| `ge25519DoubleScalarMultVartime` | value | `(-> Int Int Int Int Int)` | `Alloc,Mut,Unsafe` |  | r = [a]A + [b]B, as a P2, for 32-byte scalars `a` and `b` below 2^253 and the P3 `A`. Variable time: for verification only. |

## `Crypto.Curve25519Scalar`

`stdlib/Crypto/Curve25519Scalar.ax` — 3 public names

Crypto.Curve25519Scalar - arithmetic modulo L, the order of the
Ed25519 base point: L = 2^252 + 27742317777372353535851937790883648493.

    (sc25519Reduce r (strData digest))       ; r = SHA-512 digest mod L
    (sc25519MulAdd s k a r)                  ; s = (k a + r) mod L
    (sc25519IsCanonical (+ (strData sig) 32)) ; 1 when S < L

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `sc25519Reduce` | value | `(-> Int Int Int)` | `Alloc,Mut` |  | Write the 64 little-endian bytes at `in` reduced modulo L as 32 bytes at `out`. |
| `sc25519MulAdd` | value | `(-> Int Int Int Int Int)` | `Alloc,Mut,Unsafe` |  | Write (a b + c) mod L as 32 bytes at `out`, for 32-byte scalars `a`, `b` and `c` of any value below 2^256. |
| `sc25519IsCanonical` | value | `(-> Int Int)` | `Alloc,Mut` |  | 1 when the 32-byte scalar at `s` is below L - the canonical range RFC 8032, section 5.1.7, requires of a signature's S - and 0 otherwise. |

## `Crypto.Ed25519`

`stdlib/Crypto/Ed25519.ax` — 14 public names

Crypto.Ed25519 - Ed25519 signatures (RFC 8032, section 5.1).

    ed25519KeyGenerate                          ; (Ok <Ed25519SecretKey>)
    (ed25519Sign k "message")                   ; an Ed25519Signature, 64 bytes
    (ed25519Verify (ed25519PublicKey k) "message" sig)    ; true
    (ed25519PublicKeyFromBytes bytes)           ; (Ok pk), or Err for a bad key

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Ed25519SecretKey` | struct |  |  |  | An Ed25519 private key: a handle to the seed and what it expands to, in the secret store. Prints as `<Ed25519SecretKey>`. |
| `Ed25519PublicKey` | struct |  |  |  | An Ed25519 public key: a point's 32-byte encoding. Build one with `ed25519PublicKeyFromBytes`, which checks it. |
| `Ed25519Signature` | struct |  |  |  | An Ed25519 signature: R (32 bytes) then S (32 bytes). Build one from bytes with `ed25519SignatureFromBytes`, which checks it. |
| `ed25519KeyGenerate` | value | `(Result Ed25519SecretKey Error)` | `Alloc,Entropy,IO,Mut` |  | A fresh key from a random 32-byte seed. |
| `ed25519KeyFromSecret` | value | `(-> SecretBytes (Result Ed25519SecretKey Error))` | `Alloc,IO,Mut` |  | The key whose 32-byte seed is `s` (RFC 8032's private key). `s` is copied, not consumed. This is the deterministic route: for known-answer tests, for restoring a key saved with `ed25519KeyExport`, and for protocols that derive the seed themselves. |
| `ed25519KeyWipe` | value | `(-> Ed25519SecretKey Int)` | `Alloc,IO,Mut` |  | Erase `k` and free its storage. Any later use of `k` stops the program with status 85. Answers 0. |
| `ed25519KeyExport` | value | `(-> Ed25519SecretKey (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | The 32-byte seed of `k`, as a new `SecretBytes`: RFC 8032's private key, the standard serialisation. `ed25519KeyFromSecret` reads it back. |
| `ed25519PublicKey` | value | `(-> Ed25519SecretKey Ed25519PublicKey)` | `Alloc,Mut` |  | The public key of `k`. |
| `ed25519PublicKeyFromBytes` | value | `(-> String (Result Ed25519PublicKey Error))` | `Alloc,Mut` |  | A public key from its 32 bytes. `cryptoInvalidLength` for any other length, and `cryptoInvalidEncoding` unless the bytes are the strict encoding of a point: y below p, x recoverable, and no sign bit on x = 0. |
| `ed25519PublicKeyBytes` | value | `(-> Ed25519PublicKey String)` |  |  | The 32 bytes of a public key. |
| `ed25519SignatureFromBytes` | value | `(-> String (Result Ed25519Signature Error))` | `Alloc,Mut` |  | A signature from its 64 bytes. `cryptoInvalidLength` for any other length, and `cryptoInvalidEncoding` when R is not the strict encoding of a point or S is not below L. |
| `ed25519SignatureBytes` | value | `(-> Ed25519Signature String)` |  |  | The 64 bytes of a signature. |
| `ed25519Sign` | value | `(-> Ed25519SecretKey String Ed25519Signature)` | `Alloc,Mut` |  | The signature of `msg` under `k` (section 5.1.6): r = SHA-512(prefix \|\| msg) mod L, R = [r]B, k = SHA-512(R \|\| A \|\| msg) mod L, S = (r + k a) mod L. |
| `ed25519Verify` | value | `(-> Ed25519PublicKey String Ed25519Signature Bool)` | `Alloc,Mut` |  | Whether `sig` is a valid signature of `msg` under `pk` (section 5.1.7): false for a public key or signature of the wrong length, a public key that is not a strict encoding, an S not below L, and whenever [S]B - [k]A does not encode to R. See HOW VERIFICATION DECIDES above. |

## `Crypto.Errors`

`stdlib/Crypto/Errors.ax` — 12 public names

Crypto.Errors - the error codes every Crypto module answers.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `cryptoInvalidLength` | value | `Int` |  |  | A key, nonce, tag, salt, output length or input length that the algorithm does not accept. |
| `cryptoInvalidEncoding` | value | `Int` |  |  | Bytes that do not decode: bad hex or base64, a public key or signature that is not a canonical encoding, a malformed password record. |
| `cryptoAuthFailed` | value | `Int` |  |  | Authenticated decryption or tag verification failed. Nothing about the plaintext is released when this is answered. |
| `cryptoEntropyUnavailable` | value | `Int` |  |  | This target has no secure entropy source Axiom can reach. There is no fallback: the suite never substitutes a clock, a process id or a counter. |
| `cryptoEntropyFailed` | value | `Int` |  |  | The kernel's entropy call failed. The context carries its errno. |
| `cryptoLimitExceeded` | value | `Int` |  |  | A usage limit was reached: a message longer than the algorithm may process, or a nonce sequence that has run out. |
| `cryptoUnsupported` | value | `Int` |  |  | Parameters this implementation does not support. |
| `cryptoNoSecretStore` | value | `Int` |  |  | The secret store could not make room: the kernel refused a mapping, or the runtime's handle table is full. |
| `cryptoInvalidKey` | value | `Int` |  |  | A key that decodes but must not be used, such as an X25519 peer key that gives the all-zero shared secret. |
| `cryptoErr` | value | `(-> Int String String (Result a Error))` | `Alloc` |  | An `Err` carrying one of the codes above, with a message and the name of the function that raised it as context. |
| `cryptoAuthErr` | value | `(-> String (Result a Error))` | `Alloc` |  | The one authentication failure every open and verify answers. |
| `cryptoLengthErr` | value | `(-> String String (Result a Error))` | `Alloc,Mut` |  | A length refusal naming what was wrong. |

## `Crypto.Field25519`

`stdlib/Crypto/Field25519.ax` — 21 public names

Crypto.Field25519 - arithmetic modulo p = 2^255 - 19, the field
under X25519 and Ed25519.

    {
      (let a (rawAlloc fe25519Bytes))
      (let b (rawAlloc fe25519Bytes))
      {
        (fe25519FromBytes a (strData u))  ; 32 little-endian bytes in
        (fe25519Sq b a)  ; b = a^2
        (fe25519Invert b b)  ; b = a^-2
        (fe25519ToBytes (strData out) b)  ; 32 canonical bytes out
        (ctWipe a fe25519Bytes)
        (ctWipe b fe25519Bytes)
      }
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `fe25519Bytes` | value | `Int` |  |  | The size of one field element in bytes: ten 64-bit limbs. |
| `fe25519Set` | value | `(-> Int Int Int Int Int Int Int Int Int Int Int Int)` | `Mut,Unsafe` |  | Store the ten limbs of a constant at `out`. Answers 0. |
| `fe25519Zero` | value | `(-> Int Int)` | `Mut` |  | out = 0. |
| `fe25519One` | value | `(-> Int Int)` | `Mut` |  | out = 1. |
| `fe25519Copy` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | out = a. |
| `fe25519SqrtM1` | value | `(-> Int Int)` | `Mut` |  | A square root of -1 modulo p (ref10's sqrtm1.h). |
| `fe25519Add` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | out = a + b. |
| `fe25519Sub` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | out = a - b. |
| `fe25519Neg` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | out = -a. |
| `fe25519Mul` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | out = a * b, reduced. |
| `fe25519Sq` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | out = a^2, reduced. |
| `fe25519Sq2` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | out = 2 a^2, reduced: the square with every product doubled before the carry, as ref10's fe_sq2 does for point doubling. |
| `fe25519Mul121666` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | out = 121666 a, reduced: the constant (A + 2) / 4 of RFC 7748's ladder, where A = 486662. |
| `fe25519Invert` | value | `(-> Int Int Int)` | `Alloc,Mut` |  | out = a^(p-2) = 1/a, or 0 when a is 0 (ref10's pow225521 chain: 254 squarings and 11 multiplications, whatever `a` is). |
| `fe25519Pow22523` | value | `(-> Int Int Int)` | `Alloc,Mut` |  | out = a^((p-5)/8) = a^(2^252 - 3), the exponentiation behind square roots in point decoding (ref10's pow22523 chain). |
| `fe25519CSwap` | value | `(-> Int Int Int Int)` | `Mut` |  | Swap `f` and `g` where `m` is -1; leave both where `m` is 0. `m` must be a mask (`Crypto.Ct`). The Montgomery ladder's conditional swap. |
| `fe25519CMov` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | f = g where `m` is -1; f unchanged where `m` is 0. `m` must be a mask. The table scan's conditional move. |
| `fe25519FromBytes` | value | `(-> Int Int Int)` | `Mut` |  | out = the 32 little-endian bytes at `p`, with bit 255 ignored. The value may be anything below 2^255, p itself and the 19 values above it included; it is reduced as arithmetic proceeds. |
| `fe25519ToBytes` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | Write the canonical 32-byte little-endian encoding of `a` (its value reduced below p) at `p`. `a`'s limbs must be within 1.1 * 2^26 (even) and 1.1 * 2^25 (odd). |
| `fe25519IsNegative` | value | `(-> Int Int)` | `Alloc,Mut,Unsafe` |  | 1 when `a` is odd once reduced below p, 0 when it is even: the sign of x in an Ed25519 point encoding (RFC 8032, section 5.1.2). |
| `fe25519IsZero` | value | `(-> Int Int)` | `Alloc,Mut,Unsafe` |  | 1 when `a` is 0 modulo p, 0 otherwise, in time that does not depend on `a`. |

## `Crypto.Ghash`

`stdlib/Crypto/Ghash.ax` — 1 public names

Crypto.Ghash - GHASH, GCM's universal hash (SP 800-38D 6.4), as a
constant-time carry-less multiplication. Hazardous layer.

      {
        (let y (strAlloc 16))
        {
          (ghashUpdate (strData y) hAddr (strData aad) (strLen aad))
          (ghashUpdate (strData y) hAddr (strData ct) (strLen ct))
          (ghashUpdate (strData y) hAddr (strData lengths) 16)
        }
      }
    ; y now holds GHASH_H(A || pad || C || pad || len(A) || len(C))

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `ghashUpdate` | value | `(-> Int Int Int Int Int)` | `Mut` |  | Absorb `len` bytes at `data` into the running hash at `y` (16 bytes, big-endian, updated in place) under the hash key at `h` (16 bytes): for each 16-byte block X, Y <- (Y xor X) * H in GF(2^128). A final partial block is padded with zeros, so a caller absorbing A and then C gets GCM's padding for each. `len` is public; `y` and `h` are not. |

## `Crypto.Hkdf`

`stdlib/Crypto/Hkdf.ax` — 10 public names

Crypto.Hkdf - HKDF, the HMAC-based key derivation function, over
SHA-256 and SHA-512.

    (hkdfSha256 ikm salt "example.org v1 session key" 32)
    ; (Ok <SecretBytes>), 32 bytes derived from ikm

    (match (hkdfSha256Extract salt ikm)            ; once per input key
      ((Ok prk)
        (hkdfSha256Expand prk "client write key" 32)) ; once per use
      ((Err e) (Err e)))

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `hkdfSha256ExpandRaw` | value | `(-> Int Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` |  | HKDF-Expand with HMAC-SHA-256 (section 2.3): `len` bytes to `out` from the `prkLen`-byte key at `prk` and the `infoLen` bytes of info at `info`. T(i) = HMAC(PRK, T(i-1) \| info \| i) for i = 1, 2, ..., and the output is their concatenation cut to `len`. Answers 0. |
| `hkdfSha512ExpandRaw` | value | `(-> Int Int Int Int Int Int Int)` | `Alloc,Mut,Unsafe` |  | HKDF-Expand with HMAC-SHA-512: as `hkdfSha256ExpandRaw` with 64-byte blocks. `len` is 1 to 16320. Answers 0. |
| `hkdfSha256Raw` | value | `(-> Int Int Int Int Int Int Int Int Int)` | `Alloc,Mut` |  | HKDF with HMAC-SHA-256, extract then expand, by address: `len` bytes to `out`. The pseudorandom key lives only in scratch memory, erased before this returns. Answers 0. |
| `hkdfSha512Raw` | value | `(-> Int Int Int Int Int Int Int Int Int)` | `Alloc,Mut` |  | HKDF with HMAC-SHA-512, extract then expand, by address. `len` is 1 to 16320. Answers 0. |
| `hkdfSha256Extract` | value | `(-> String SecretBytes (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | HKDF-Extract with HMAC-SHA-256 (section 2.2): the 32-byte pseudorandom key HMAC(salt, ikm). An empty salt is 32 zero bytes. |
| `hkdfSha256Expand` | value | `(-> SecretBytes String Int (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | HKDF-Expand with HMAC-SHA-256 (section 2.3): `len` bytes from `prk` for the context `info`. `prk` must be at least 32 bytes and `len` 1 to 8160; otherwise `cryptoInvalidLength`. |
| `hkdfSha256` | value | `(-> SecretBytes String String Int (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | HKDF with HMAC-SHA-256: extract from `ikm` with `salt`, then expand `len` bytes for the context `info`. `len` must be 1 to 8160; otherwise `cryptoInvalidLength`. |
| `hkdfSha512Extract` | value | `(-> String SecretBytes (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | HKDF-Extract with HMAC-SHA-512: the 64-byte pseudorandom key HMAC(salt, ikm). An empty salt is 64 zero bytes. |
| `hkdfSha512Expand` | value | `(-> SecretBytes String Int (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | HKDF-Expand with HMAC-SHA-512: `len` bytes from `prk` for the context `info`. `prk` must be at least 64 bytes and `len` 1 to 16320; otherwise `cryptoInvalidLength`. |
| `hkdfSha512` | value | `(-> SecretBytes String String Int (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | HKDF with HMAC-SHA-512: extract from `ikm` with `salt`, then expand `len` bytes for the context `info`. `len` must be 1 to 16320; otherwise `cryptoInvalidLength`. |

## `Crypto.Hmac`

`stdlib/Crypto/Hmac.ax` — 38 public names

Crypto.Hmac - HMAC-SHA-256 and HMAC-SHA-512.

    (match (hmacSha256KeyFromSecret k)
      ; k : SecretBytes
      ((Ok key)
        {
          (let tag (hmacSha256 key "message"))  ; 32 bytes
          (hmacSha256Verify key "message" tag)  ; true
        }
      )
      ((Err e) false))

    {
      (let m (hmacSha256New key))  ; streaming
      {
        (hmacSha256Update m "mess")
        (hmacSha256Update m "age")
        (hmacSha256Final m)  ; the same tag
      }
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `HmacSha256Key` | struct |  |  |  | An HMAC-SHA-256 key: a handle to its bytes and their precomputed inner and outer states in the secret store. Prints as `<HmacSha256Key>`. |
| `HmacSha512Key` | struct |  |  |  | An HMAC-SHA-512 key. Prints as `<HmacSha512Key>`. |
| `hmacSha256KeyGenerate` | value | `(Result HmacSha256Key Error)` | `Alloc,Entropy,IO,Mut` |  | A fresh random HMAC-SHA-256 key of 32 bytes, the hash's output length. |
| `hmacSha256KeyFromSecret` | value | `(-> SecretBytes (Result HmacSha256Key Error))` | `Alloc,IO,Mut` |  | An HMAC-SHA-256 key holding a copy of `s`, which may be any length from 1 byte. This is also the deterministic route for known-answer tests and protocols that derive the key. |
| `hmacSha256KeyExport` | value | `(-> HmacSha256Key (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | The key bytes of `k`, as a new `SecretBytes`. |
| `hmacSha256KeyWipe` | value | `(-> HmacSha256Key Int)` | `Alloc,IO,Mut` |  | Erase `k` and free its storage. Any later use of `k` stops the program with status 85. Answers 0. |
| `hmacSha512KeyGenerate` | value | `(Result HmacSha512Key Error)` | `Alloc,Entropy,IO,Mut` |  | A fresh random HMAC-SHA-512 key of 64 bytes, the hash's output length. |
| `hmacSha512KeyFromSecret` | value | `(-> SecretBytes (Result HmacSha512Key Error))` | `Alloc,IO,Mut` |  | An HMAC-SHA-512 key holding a copy of `s`, which may be any length from 1 byte. |
| `hmacSha512KeyExport` | value | `(-> HmacSha512Key (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | The key bytes of `k`, as a new `SecretBytes`. |
| `hmacSha512KeyWipe` | value | `(-> HmacSha512Key Int)` | `Alloc,IO,Mut` |  | Erase `k` and free its storage. Answers 0. |
| `hmacSha256` | value | `(-> HmacSha256Key String String)` | `Alloc,Mut` |  | The 32-byte HMAC-SHA-256 tag of `msg` under `k`. |
| `hmacSha256Verify` | value | `(-> HmacSha256Key String String Bool)` | `Alloc,Mut` |  | Whether `tag` is the HMAC-SHA-256 tag of `msg` under `k`. A tag that is not 32 bytes answers false. The comparison takes the same time wherever the tags differ. |
| `hmacSha512` | value | `(-> HmacSha512Key String String)` | `Alloc,Mut` |  | The 64-byte HMAC-SHA-512 tag of `msg` under `k`. |
| `hmacSha512Verify` | value | `(-> HmacSha512Key String String Bool)` | `Alloc,Mut` |  | Whether `tag` is the HMAC-SHA-512 tag of `msg` under `k`. A tag that is not 64 bytes answers false. The comparison takes the same time wherever the tags differ. |
| `hmacSha256Raw` | value | `(-> Int Int Int Int Int Int)` | `Alloc,Mut` |  | The HMAC-SHA-256 tag under the `keyLen`-byte key at `key` of `n` bytes at `p`, written to the 32 bytes at `out`: the key by address, for Crypto modules holding a key in their own secret memory. Any key length, the empty key included, is used as given. Answers 0. |
| `hmacSha512Raw` | value | `(-> Int Int Int Int Int Int)` | `Alloc,Mut` |  | The HMAC-SHA-512 tag under the `keyLen`-byte key at `key` of `n` bytes at `p`, written to the 64 bytes at `out`. Answers 0. |
| `HmacSha256` | struct |  |  |  | An HMAC-SHA-256 computation in progress. Make one with `hmacSha256New`. |
| `HmacSha512` | struct |  |  |  | An HMAC-SHA-512 computation in progress. Make one with `hmacSha512New`. |
| `hmacSha256New` | value | `(-> HmacSha256Key HmacSha256)` | `Alloc,Mut` |  | A streaming HMAC-SHA-256 under `k`. |
| `hmacSha256NewRaw` | value | `(-> Int Int HmacSha256)` | `Alloc,Mut` |  | A streaming HMAC-SHA-256 under the `keyLen`-byte key at `key`, used as given: the hazardous form for Crypto modules, such as HKDF, that hold a key in their own secret memory. |
| `hmacSha256Chains` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The 64 bytes an HMAC-SHA-256 key precomputes (FIPS 198-1 section 6): the inner chaining value, then the outer one, for the `keyLen`-byte key at `key`, written to `out`. With `hmacSha256NewChains` this lets a Crypto module key many MACs while doing the key schedule once, and keep the key-derived bytes in memory it manages. Answers 0. |
| `hmacSha256NewChains` | value | `(-> Int HmacSha256)` | `Alloc,Mut` |  | A streaming HMAC-SHA-256 over the 64 precomputed bytes at `chains` that `hmacSha256Chains` wrote. |
| `hmacSha256UpdateAddr` | value | `(-> HmacSha256 Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`. Answers 0, or -1 when `m` is not a live HMAC-SHA-256 state, and then absorbs nothing. |
| `hmacSha256Update` | value | `(-> HmacSha256 String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `m` is not a live HMAC-SHA-256 state. |
| `hmacSha256FinalAddr` | value | `(-> HmacSha256 Int Int)` | `Alloc,Mut` |  | Write the tag of everything absorbed to the 32 bytes at `out`; `m` is then ready for another message under the same key. Answers 0, or -1 when `m` is not a live HMAC-SHA-256 state. |
| `hmacSha256Final` | value | `(-> HmacSha256 String)` | `Alloc,Mut` |  | The 32-byte tag of everything absorbed; `m` is then ready for another message under the same key. A value that is not a live HMAC-SHA-256 state answers the empty string. |
| `hmacSha256Copy` | value | `(-> HmacSha256 HmacSha256)` | `Alloc,Mut` |  | An independent copy of `m`, which goes on from the same point. |
| `hmacSha256Wipe` | value | `(-> HmacSha256 Int)` | `Mut` |  | Erase everything `m` holds, the key's chaining values included; every later operation on it is refused. Answers 0, or -1 with nothing written when `m` is not a state. |
| `hmacSha512New` | value | `(-> HmacSha512Key HmacSha512)` | `Alloc,Mut` |  | A streaming HMAC-SHA-512 under `k`. |
| `hmacSha512NewRaw` | value | `(-> Int Int HmacSha512)` | `Alloc,Mut` |  | A streaming HMAC-SHA-512 under the `keyLen`-byte key at `key`, used as given: the hazardous form for Crypto modules. |
| `hmacSha512Chains` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The 128 bytes an HMAC-SHA-512 key precomputes (FIPS 198-1 section 6): the inner chaining value, then the outer one, for the `keyLen`-byte key at `key`, written to `out`. With `hmacSha512NewChains` this lets a Crypto module key many MACs while doing the key schedule once, and keep the key-derived bytes in memory it manages. Answers 0. |
| `hmacSha512NewChains` | value | `(-> Int HmacSha512)` | `Alloc,Mut` |  | A streaming HMAC-SHA-512 over the 128 precomputed bytes at `chains` that `hmacSha512Chains` wrote. |
| `hmacSha512UpdateAddr` | value | `(-> HmacSha512 Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`. Answers 0, or -1 when `m` is not a live HMAC-SHA-512 state, and then absorbs nothing. |
| `hmacSha512Update` | value | `(-> HmacSha512 String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `m` is not a live HMAC-SHA-512 state. |
| `hmacSha512FinalAddr` | value | `(-> HmacSha512 Int Int)` | `Alloc,Mut` |  | Write the tag of everything absorbed to the 64 bytes at `out`; `m` is then ready for another message under the same key. Answers 0, or -1 when `m` is not a live HMAC-SHA-512 state. |
| `hmacSha512Final` | value | `(-> HmacSha512 String)` | `Alloc,Mut` |  | The 64-byte tag of everything absorbed; `m` is then ready for another message under the same key. A value that is not a live HMAC-SHA-512 state answers the empty string. |
| `hmacSha512Copy` | value | `(-> HmacSha512 HmacSha512)` | `Alloc,Mut` |  | An independent copy of `m`, which goes on from the same point. |
| `hmacSha512Wipe` | value | `(-> HmacSha512 Int)` | `Mut` |  | Erase everything `m` holds, the key's chaining values included; every later operation on it is refused. Answers 0, or -1 with nothing written when `m` is not a state. |

## `Crypto.Obfuscate`

`stdlib/Crypto/Obfuscate.ax` — 8 public names

Crypto.Obfuscate - authenticated envelopes for embedded binary assets.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `ObfuscationKey` | struct |  |  |  | A sealed 256-bit master key in the secret store. Wipe it after use. |
| `obfuscationMaxBytes` | value | `Int` |  |  | The largest plaintext accepted by the envelope format: 64 MiB. |
| `obfuscationKeyGenerate` | value | `(Result ObfuscationKey Error)` | `Alloc,Entropy,IO,Mut` |  | A fresh 32-byte master key from the operating system's entropy source. |
| `obfuscationKeyFromSecret` | value | `(-> SecretBytes (Result ObfuscationKey Error))` | `Alloc,IO,Mut` |  | Copy a 32-byte secret into a master key, leaving the secret live. |
| `obfuscationKeyFromShares` | value | `(-> String String (Result ObfuscationKey Error))` | `Alloc,IO,Mut,Unsafe` |  | Reconstruct a master key from two 32-byte XOR shares directly in the secret store. Neither share alone reveals the key when the other was drawn randomly. Embedding both shares provides obfuscation only. |
| `obfuscationKeyWipe` | value | `(-> ObfuscationKey Int)` | `Alloc,IO,Mut` |  | Erase and free the master key. Later use stops with status 85. |
| `obfuscationSeal` | value | `(-> ObfuscationKey String String (Result String Error))` | `Alloc,Entropy,IO,Mut` |  | Pack plaintext under a fresh random nonce, bound to `context`. An empty context is allowed. Seal at most 2^32 assets under one key; use a fresh master key for each build, as the packing tool does. |
| `obfuscationOpen` | value | `(-> ObfuscationKey String String (Result String Error))` | `Alloc,IO,Mut` |  | Authenticate and open a v1 envelope for `context`. Wrong keys, contexts, nonces, ciphertext or tags answer cryptoAuthFailed without returning plaintext. Truncated or unknown headers answer cryptoInvalidEncoding; oversized inputs answer cryptoLimitExceeded. |

## `Crypto.Poly1305`

`stdlib/Crypto/Poly1305.ax` — 6 public names

Crypto.Poly1305 - the Poly1305 one-time authenticator of RFC 8439,
in constant time with 26-bit limbs. Hazardous layer.

    {
      (let tag (strAlloc 16))
      (let st (strAlloc poly1305StateBytes))
      (poly1305Mac (strData tag) oneTimeKeyAddr (strData msg) (strLen msg) (strData st))
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `poly1305StateBytes` | value | `Int` |  |  | The state, 16 words:   words 0-4    r, clamped, in 26-bit limbs   words 5-9    the accumulator h, in 26-bit limbs   words 10-13  s, the key's second half, as 32-bit words   words 14-15  scratch for a padded final block |
| `poly1305Init` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | Start a state from the 32-byte one-time key at `key`: r is the first 16 bytes with the clamping of RFC 8439 2.5, s the last 16, and the accumulator zero. |
| `poly1305Blocks` | value | `(-> Int Int Int Int Int)` | `Mut,Unsafe` |  | Absorb the `n` whole 16-byte blocks at `p`, each read as a little-endian number plus `hibit` * 2^104 in the top limb: 2^24 for the 2^128 bit every full block carries, 0 for a final block that already has its 0x01 byte. h <- (h + block) * r mod 2^130 - 5, left partly reduced: every limb below 2^26 but the second, which may be slightly above. |
| `poly1305AbsorbPadded` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | Absorb `len` bytes at `p` the way the AEAD of RFC 8439 2.8 does: the whole blocks, then any remainder padded with zeros to 16 bytes and absorbed as a full block (with its 2^128 bit). That padding is `pad16` of the RFC; the standalone MAC pads differently and uses `poly1305Mac`. |
| `poly1305Finish` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | Finish: carry the accumulator fully, reduce it below p = 2^130 - 5 with a masked choice between h and h - p, add s modulo 2^128, and write the 16-byte tag at `tag` in little-endian order. The state is wiped. |
| `poly1305Mac` | value | `(-> Int Int Int Int Int Int)` | `Mut,Unsafe` |  | The Poly1305 tag of the `len` bytes at `msg` under the 32-byte one-time key at `key`, written to the 16 bytes at `tag` (RFC 8439 2.5): whole blocks with their 2^128 bit, then any remainder with a 0x01 byte after it, zero-padded, and no 2^128 bit. `st` is scratch, wiped before this returns. |

## `Crypto.Random`

`stdlib/Crypto/Random.ax` — 9 public names

Crypto.Random - cryptographically secure random values.

    (secureRandomBytes 32)    ; (Ok <32 bytes from the kernel>)
    (randomBelow 6)           ; (Ok 0..5, each equally likely)
    (randomTokenUrl 16)       ; (Ok "q0V9..."), 128 bits, URL-safe

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `randomFill` | value | `(-> Int Int (Result Int Error))` | `Alloc,Entropy,IO,Mut` |  | Fill `n` bytes at `p` with secure random bytes. The low-level entry every other function here and every key generator uses. On `Err` the bytes at `p` are unspecified and must not be used. |
| `randomAvailable` | value | `Bool` | `Entropy,Mut` |  | Whether this target has a secure entropy source at all. A program can ask before it depends on one. |
| `secureRandomBytes` | value | `(-> Int (Result String Error))` | `Alloc,Entropy,IO,Mut` |  | `n` secure random bytes. |
| `randomWord` | value | `(Result Int Error)` | `Alloc,Entropy,IO,Mut` |  | A uniformly random 64-bit word (any Int, negative included). |
| `randomBelow` | value | `(-> Int (Result Int Error))` | `Alloc,Entropy,IO,Mut` |  | A uniformly random Int in 0..bound-1. `bound` must be at least 1. |
| `randomRange` | value | `(-> Int Int (Result Int Error))` | `Alloc,Entropy,IO,Mut` |  | A uniformly random Int in lo..hi-1. `hi` must be above `lo`, and the range must fit in an Int. |
| `randomShuffle` | value | `(-> (Vec a) (Result Int Error))` | `Alloc,Entropy,IO,Mut` |  | Shuffle `v` in place into a uniformly random order (Fisher-Yates: position i swaps with a uniform choice among 0..i). Answers `v`'s length. Random words are drawn 32 at a time, so a long vector costs one kernel call per 32 or so positions rather than one each. |
| `randomTokenHex` | value | `(-> Int (Result String Error))` | `Alloc,Entropy,IO,Mut` |  | `n` random bytes as lower-case hex (2n characters). |
| `randomTokenUrl` | value | `(-> Int (Result String Error))` | `Alloc,Entropy,IO,Mut` |  | `n` random bytes as URL-safe base64 without padding. |

## `Crypto.Secret`

`stdlib/Crypto/Secret.ax` — 17 public names

Crypto.Secret - where key material lives.

    {
      (let k (unwrapOr (secretRandom 32) ...))
      {
        (println "{k}")  ; prints <SecretBytes>, never the bytes
        (secretLen k)  ; 32
        (secretWipe k)  ; zeroed, unlocked, unmapped
      }
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `SecretBytes` | struct |  |  |  | A secret of any length, with no algorithm attached. Algorithms take their own key types, made from one of these with an explicit conversion that checks the length. |
| `secretBlockNew` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` | `;@axiom:pre((&& (>= kind 16) (<= kind 63)))` | A fresh zeroed secret of `n` payload bytes under handle kind `kind`, as a handle word. |
| `secretBlockAddr` | value | `(-> Int Int Int)` | `Unsafe` |  | The address of the payload of live secret `h` of kind `kind`. A dead, forged or other-kind handle stops the program with status 85. |
| `secretBlockLen` | value | `(-> Int Int Int)` | `Unsafe` |  | The payload length of live secret `h`. |
| `secretBlockLocked` | value | `(-> Int Int Bool)` | `Unsafe` |  | Whether the kernel locked live secret `h` out of swap. |
| `secretBlockFree` | value | `(-> Int Int Int)` | `Alloc,IO,Mut,Unsafe` |  | Erase and free live secret `h`: zero the whole mapping, unlock it, unmap it, and retire the handle so any later use stops the program. A second free stops it too. Answers 0. |
| `secretBlockFrom` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut` |  | A fresh secret of kind `kind` holding a copy of `n` bytes at `p`. |
| `secretBlockRandom` | value | `(-> Int Int (Result Int Error))` | `Alloc,Entropy,IO,Mut` |  | A fresh secret of kind `kind` holding `n` random bytes, drawn straight into the mapping so they are never anywhere else. |
| `secretFromString` | value | `(-> String (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | A secret holding a copy of `s`'s bytes. The string itself is not touched: if it held the only other copy, the caller decides whether to overwrite it. |
| `secretRandom` | value | `(-> Int (Result SecretBytes Error))` | `Alloc,Entropy,IO,Mut` |  | A secret of `n` random bytes from `Crypto.Random`. |
| `secretFromAddr` | value | `(-> Int Int (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | A secret holding a copy of `n` bytes at `p`. For Crypto modules that derive a secret into their own scratch memory and hand it out. |
| `secretLen` | value | `(-> SecretBytes Int)` |  |  | How many bytes `s` holds. A secret's length is not secret. |
| `secretAddr` | value | `(-> SecretBytes Int)` |  |  | The payload address of `s`, for a Crypto module reading it. Valid only while `s` stays live. |
| `secretEq` | value | `(-> SecretBytes SecretBytes Bool)` | `Mut` |  | Whether two secrets hold the same bytes, in time that depends only on their lengths. |
| `secretIsLocked` | value | `(-> SecretBytes Bool)` |  |  | Whether the kernel locked `s` out of swap. |
| `secretWipe` | value | `(-> SecretBytes Int)` | `Alloc,IO,Mut` |  | Erase `s` and free its storage. Any later use of `s`, or of a copy of the handle, stops the program with status 85. Answers 0. |
| `secretExposeCopy` | value | `(-> SecretBytes String)` | `Alloc,Mut` |  | A COPY of the secret's bytes in an ordinary string. This is the one way a secret's value leaves the store, for writing a key to a file you have decided to trust. The copy is arena memory: it is not locked, not wiped by `secretWipe`, and can be printed. Prefer a typed key's own export, which says what the bytes are. |

## `Crypto.Sha2`

`stdlib/Crypto/Sha2.ax` — 39 public names

Crypto.Sha2 - SHA-256, SHA-384 and SHA-512.

    (hexEncode (sha256 "abc"))
    ; "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    {
      (let h sha512New)
      {
        (sha512Update h "a")
        (sha512Update h "bc")
        (sha512Final h)  ; the same 64 bytes as (sha512 "abc")
      }
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Sha256` | struct |  |  |  | A SHA-256 hash in progress. Make one with `sha256New`. |
| `sha256New` | value | `Sha256` | `Alloc,Mut` |  | A fresh SHA-256 hash with nothing absorbed. |
| `sha256UpdateAddr` | value | `(-> Sha256 Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`: `sha256Update` for a caller holding raw memory, such as another Crypto module hashing a key in the secret store. Answers 0, or -1 when `h` is not a SHA-256 state or the message would pass the length limit, and then absorbs nothing. |
| `sha256Update` | value | `(-> Sha256 String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `h` is not a SHA-256 state or the message would pass the length limit, and then absorbs nothing. |
| `sha256Final` | value | `(-> Sha256 String)` | `Alloc,Mut` |  | The 32-byte digest of everything absorbed. `h` is then reset to a fresh hash, its partial block wiped, ready for another message. A value that is not a SHA-256 state answers the empty string. |
| `sha256Copy` | value | `(-> Sha256 Sha256)` | `Alloc,Mut` |  | An independent copy of `h`, which goes on from the same point. Prime one state with a shared prefix, then copy it once per message. |
| `sha256Wipe` | value | `(-> Sha256 Int)` | `Mut` |  | Erase everything `h` holds and leave it a fresh hash. Answers 0, or -1 with nothing written when `h` is not a SHA-256 state. |
| `sha256Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The SHA-256 digest of `n` bytes at `p`, written to the 32 bytes at `out`. Answers 0. The scratch state is wiped before it returns. |
| `sha256` | value | `(-> String String)` | `Alloc,Mut` |  | The 32-byte SHA-256 digest of `msg`. |
| `Sha512` | struct |  |  |  | A SHA-512 hash in progress. Make one with `sha512New`. |
| `Sha384` | struct |  |  |  | A SHA-384 hash in progress. Make one with `sha384New`. |
| `sha512New` | value | `Sha512` | `Alloc,Mut` |  | A fresh SHA-512 hash with nothing absorbed. |
| `sha512UpdateAddr` | value | `(-> Sha512 Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`. Answers 0, or -1 when `h` is not a SHA-512 state or the message would pass the length limit, and then absorbs nothing. |
| `sha512Update` | value | `(-> Sha512 String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `h` is not a SHA-512 state or the message would pass the length limit, and then absorbs nothing. |
| `sha512Final` | value | `(-> Sha512 String)` | `Alloc,Mut` |  | The 64-byte digest of everything absorbed. `h` is then reset to a fresh hash, its partial block wiped. A value that is not a SHA-512 state answers the empty string. |
| `sha512Copy` | value | `(-> Sha512 Sha512)` | `Alloc,Mut` |  | An independent copy of `h`, which goes on from the same point. |
| `sha512Wipe` | value | `(-> Sha512 Int)` | `Mut` |  | Erase everything `h` holds and leave it a fresh hash. Answers 0, or -1 with nothing written when `h` is not a SHA-512 state. |
| `sha512Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The SHA-512 digest of `n` bytes at `p`, written to the 64 bytes at `out`. Answers 0. The scratch state is wiped before it returns. |
| `sha512` | value | `(-> String String)` | `Alloc,Mut` |  | The 64-byte SHA-512 digest of `msg`. |
| `sha384New` | value | `Sha384` | `Alloc,Mut` |  | A fresh SHA-384 hash with nothing absorbed. |
| `sha384UpdateAddr` | value | `(-> Sha384 Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`. Answers 0, or -1 when `h` is not a SHA-384 state or the message would pass the length limit, and then absorbs nothing. |
| `sha384Update` | value | `(-> Sha384 String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `h` is not a SHA-384 state or the message would pass the length limit, and then absorbs nothing. |
| `sha384Final` | value | `(-> Sha384 String)` | `Alloc,Mut` |  | The 48-byte digest of everything absorbed. `h` is then reset to a fresh hash, its partial block wiped. A value that is not a SHA-384 state answers the empty string. |
| `sha384Copy` | value | `(-> Sha384 Sha384)` | `Alloc,Mut` |  | An independent copy of `h`, which goes on from the same point. |
| `sha384Wipe` | value | `(-> Sha384 Int)` | `Mut` |  | Erase everything `h` holds and leave it a fresh hash. Answers 0, or -1 with nothing written when `h` is not a SHA-384 state. |
| `sha384Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The SHA-384 digest of `n` bytes at `p`, written to the 48 bytes at `out`. Answers 0. The scratch state is wiped before it returns. |
| `sha384` | value | `(-> String String)` | `Alloc,Mut` |  | The 48-byte SHA-384 digest of `msg`. |
| `sha256RawSize` | value | `Int` |  |  | The bytes a raw SHA-256 state occupies. |
| `sha256RawInit` | value | `(-> Int Int)` | `Mut` |  | Make the `sha256RawSize` bytes at `st` a fresh SHA-256 state. Answers 0. |
| `sha256RawUpdate` | value | `(-> Int Int Int Int)` | `Mut` |  | Absorb `n` bytes at `p` into the raw state at `st`. Answers 0, or -1 past the length limit, and then absorbs nothing. |
| `sha256RawFinal` | value | `(-> Int Int Int)` | `Mut` |  | Write the digest of the raw state at `st` to the 32 bytes at `out`, then reset the state to a fresh one. Answers 0. |
| `sha256RawResume` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | Make the raw state at `st` one that has absorbed `count` bytes and holds the chaining value in the 32 bytes at `chain`, most significant byte of each word first: the state `sha256RawChain` saved. `count` must be a multiple of 64. Answers 0. |
| `sha256RawChain` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | Write the chaining value of the raw state at `st` to the 32 bytes at `out`, most significant byte of each word first. Meaningful only after a whole number of blocks; answers 0, or -1 with nothing written when a partial block is waiting. |
| `sha512RawSize` | value | `Int` |  |  | The bytes a raw SHA-512 or SHA-384 state occupies. |
| `sha512RawInit` | value | `(-> Int Int)` | `Mut` |  | Make the `sha512RawSize` bytes at `st` a fresh SHA-512 state. Answers 0. |
| `sha512RawUpdate` | value | `(-> Int Int Int Int)` | `Mut` |  | Absorb `n` bytes at `p` into the raw SHA-512 or SHA-384 state at `st`. Answers 0, or -1 past the length limit, and then absorbs nothing. |
| `sha512RawFinal` | value | `(-> Int Int Int)` | `Mut` |  | Write the SHA-512 digest of the raw state at `st` to the 64 bytes at `out`, then reset the state to a fresh SHA-512 one. Answers 0. |
| `sha512RawResume` | value | `(-> Int Int Int Int)` | `Mut,Unsafe` |  | Make the raw state at `st` one that has absorbed `count` bytes and holds the chaining value in the 64 bytes at `chain`, most significant byte of each word first. `count` must be a multiple of 128. Answers 0. |
| `sha512RawChain` | value | `(-> Int Int Int)` | `Mut,Unsafe` |  | Write the chaining value of the raw SHA-512 state at `st` to the 64 bytes at `out`, most significant byte of each word first. Answers 0, or -1 with nothing written when a partial block is waiting. |

## `Crypto.Sha3`

`stdlib/Crypto/Sha3.ax` — 39 public names

Crypto.Sha3 - SHA-3 and SHAKE, and the Keccak-f[1600] permutation
under them.

    (hexEncode (sha3_256 "abc"))
    ; "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"

    (hexEncode (shake128 "" 16))
    ; "7f9c2ba4e88f827d616045507605853e"

    {
      (let x shake256New)  ; an XOF, read in pieces
      {
        (shake256Absorb x "seed")
        (shake256Squeeze x 32)  ; output bytes 0-31
        (shake256Squeeze x 32)  ; output bytes 32-63
      }
    }

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `keccakF1600` | value | `(-> Int Int)` | `Mut,Unsafe` |  | Keccak-f[1600], Algorithm 7 with 24 rounds, on the 25 lanes at `st`: lane (x, y) in word x + 5y, as a 64-bit word. On a little-endian machine that is also FIPS 202's byte order for the state. |
| `sha3_224Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The SHA3-224 digest of `n` bytes at `p`, written to the 28 bytes at `out`. Answers 0. |
| `sha3_256Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The SHA3-256 digest of `n` bytes at `p`, written to the 32 bytes at `out`. Answers 0. |
| `sha3_384Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The SHA3-384 digest of `n` bytes at `p`, written to the 48 bytes at `out`. Answers 0. |
| `sha3_512Addr` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | The SHA3-512 digest of `n` bytes at `p`, written to the 64 bytes at `out`. Answers 0. |
| `sha3_224` | value | `(-> String String)` | `Alloc,Mut` |  | The 28-byte SHA3-224 digest of `msg`. |
| `sha3_256` | value | `(-> String String)` | `Alloc,Mut` |  | The 32-byte SHA3-256 digest of `msg`. |
| `sha3_384` | value | `(-> String String)` | `Alloc,Mut` |  | The 48-byte SHA3-384 digest of `msg`. |
| `sha3_512` | value | `(-> String String)` | `Alloc,Mut` |  | The 64-byte SHA3-512 digest of `msg`. |
| `Sha3` | struct |  |  |  | A SHA-3 hash in progress, of any of the four sizes. Make one with `sha3_224New`, `sha3_256New`, `sha3_384New` or `sha3_512New`. |
| `sha3_224New` | value | `Sha3` | `Alloc,Mut` |  | A fresh SHA3-224 hash. |
| `sha3_256New` | value | `Sha3` | `Alloc,Mut` |  | A fresh SHA3-256 hash. |
| `sha3_384New` | value | `Sha3` | `Alloc,Mut` |  | A fresh SHA3-384 hash. |
| `sha3_512New` | value | `Sha3` | `Alloc,Mut` |  | A fresh SHA3-512 hash. |
| `sha3UpdateAddr` | value | `(-> Sha3 Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`. Answers 0, or -1 when `h` is not a SHA-3 state, and then absorbs nothing. |
| `sha3Update` | value | `(-> Sha3 String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `h` is not a SHA-3 state. |
| `sha3Final` | value | `(-> Sha3 String)` | `Alloc,Mut,Unsafe` |  | The digest of everything absorbed: 28, 32, 48 or 64 bytes, as `h` was made. `h` is then reset to a fresh hash of the same size. A value that is not a SHA-3 state answers the empty string. |
| `sha3Copy` | value | `(-> Sha3 Sha3)` | `Alloc,Mut` |  | An independent copy of `h`, which goes on from the same point. |
| `sha3Wipe` | value | `(-> Sha3 Int)` | `Mut,Unsafe` |  | Erase everything `h` holds and leave it a fresh hash of the same size. Answers 0, or -1 with nothing written when `h` is not a SHA-3 state. |
| `shake128Addr` | value | `(-> Int Int Int Int Int)` | `Alloc,Mut` |  | `outLen` bytes of SHAKE128 over `n` bytes at `p`, written to `out`. Answers 0. |
| `shake256Addr` | value | `(-> Int Int Int Int Int)` | `Alloc,Mut` |  | `outLen` bytes of SHAKE256 over `n` bytes at `p`, written to `out`. Answers 0. |
| `shake128` | value | `(-> String Int String)` | `Alloc,Mut` |  | The first `outLen` bytes of SHAKE128 over `msg`. A negative length answers the empty string. |
| `shake256` | value | `(-> String Int String)` | `Alloc,Mut` |  | The first `outLen` bytes of SHAKE256 over `msg`. A negative length answers the empty string. |
| `Shake128` | struct |  |  |  | A SHAKE128 extendable-output function in progress: absorb input, then squeeze output in as many pieces as wanted. |
| `Shake256` | struct |  |  |  | A SHAKE256 extendable-output function in progress. |
| `shake128New` | value | `Shake128` | `Alloc,Mut` |  | A fresh SHAKE128 with nothing absorbed. |
| `shake256New` | value | `Shake256` | `Alloc,Mut` |  | A fresh SHAKE256 with nothing absorbed. |
| `shake128AbsorbAddr` | value | `(-> Shake128 Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`. Answers 0, or -1 when `x` is not a SHAKE128 state or has begun squeezing, and then absorbs nothing. |
| `shake128Absorb` | value | `(-> Shake128 String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `x` is not a SHAKE128 state or has begun squeezing. |
| `shake128SqueezeAddr` | value | `(-> Shake128 Int Int Int)` | `Mut` |  | Squeeze the next `n` bytes of output to address `out`; the first squeeze ends the input. Answers 0, or -1 when `x` is not a SHAKE128 state or `n` is negative. |
| `shake128Squeeze` | value | `(-> Shake128 Int String)` | `Alloc,Mut` |  | The next `n` bytes of output; the first squeeze ends the input. A negative `n`, or a value that is not a SHAKE128 state, answers the empty string. |
| `shake128Copy` | value | `(-> Shake128 Shake128)` | `Alloc,Mut` |  | An independent copy of `x`, which goes on from the same point. |
| `shake128Wipe` | value | `(-> Shake128 Int)` | `Mut` |  | Erase everything `x` holds and leave it a fresh SHAKE128. Answers 0, or -1 with nothing written when `x` is not a sponge state. |
| `shake256AbsorbAddr` | value | `(-> Shake256 Int Int Int)` | `Mut` |  | Absorb `n` bytes at address `p`. Answers 0, or -1 when `x` is not a SHAKE256 state or has begun squeezing, and then absorbs nothing. |
| `shake256Absorb` | value | `(-> Shake256 String Int)` | `Mut` |  | Absorb `msg`. Answers 0, or -1 when `x` is not a SHAKE256 state or has begun squeezing. |
| `shake256SqueezeAddr` | value | `(-> Shake256 Int Int Int)` | `Mut` |  | Squeeze the next `n` bytes of output to address `out`; the first squeeze ends the input. Answers 0, or -1 when `x` is not a SHAKE256 state or `n` is negative. |
| `shake256Squeeze` | value | `(-> Shake256 Int String)` | `Alloc,Mut` |  | The next `n` bytes of output; the first squeeze ends the input. A negative `n`, or a value that is not a SHAKE256 state, answers the empty string. |
| `shake256Copy` | value | `(-> Shake256 Shake256)` | `Alloc,Mut` |  | An independent copy of `x`, which goes on from the same point. |
| `shake256Wipe` | value | `(-> Shake256 Int)` | `Mut` |  | Erase everything `x` holds and leave it a fresh SHAKE256. Answers 0, or -1 with nothing written when `x` is not a sponge state. |

## `Crypto.X25519`

`stdlib/Crypto/X25519.ax` — 13 public names

Crypto.X25519 - Diffie-Hellman key agreement over Curve25519
(RFC 7748).

    x25519KeyGenerate                   ; (Ok <X25519SecretKey>)
    (x25519PublicKey k)                 ; the X25519PublicKey to send
    (x25519PublicKeyFromBytes bytes)    ; (Ok pk) for any 32 bytes
    (x25519 k pk)                       ; (Ok <SecretBytes>), 32 bytes

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `X25519SecretKey` | struct |  |  |  | An X25519 private key: a handle to 32 secret bytes and their public key in the secret store. Prints as `<X25519SecretKey>`. |
| `X25519PublicKey` | struct |  |  |  | An X25519 public key: a u-coordinate, 32 little-endian bytes. Build one with `x25519PublicKeyFromBytes`. |
| `x25519ScalarMultAddr` | value | `(-> Int Int Int Int)` | `Alloc,Mut,Unsafe` |  | X25519(k, u) at raw addresses: write the u-coordinate of [k]u at `out`, where `k` is clamped first and bit 255 of `u` is ignored. No all-zero check. Both inputs are read before `out` is written, so `out` may be either of them. |
| `x25519ScalarMult` | value | `(-> String String (Result String Error))` | `Alloc,Mut` |  | X25519(k, u) on byte strings: the raw function of RFC 7748, section 5, with no all-zero check. `Err` with `cryptoInvalidLength` unless both are 32 bytes. For known-answer tests and protocols that specify the raw function; key agreement wants `x25519`. |
| `x25519BasePoint` | value | `String` | `Alloc,Mut,Unsafe` |  | The u-coordinate of the base point, 9, as 32 bytes. |
| `x25519KeyGenerate` | value | `(Result X25519SecretKey Error)` | `Alloc,Entropy,IO,Mut` |  | A fresh random private key and its public key. |
| `x25519KeyFromSecret` | value | `(-> SecretBytes (Result X25519SecretKey Error))` | `Alloc,IO,Mut` |  | The private key held in `s`, which must be 32 bytes, and its public key. `s` is copied, not consumed. Any 32 bytes are a private key (RFC 7748 clamps them when they are used), so this is also the deterministic route for known-answer tests and for protocols that derive the key themselves. |
| `x25519KeyWipe` | value | `(-> X25519SecretKey Int)` | `Alloc,IO,Mut` |  | Erase `k` and free its storage. Any later use of `k` stops the program with status 85. Answers 0. |
| `x25519KeyExport` | value | `(-> X25519SecretKey (Result SecretBytes Error))` | `Alloc,IO,Mut` |  | The 32 private-key bytes of `k`, as a new `SecretBytes`: the standard serialisation (RFC 7748, section 5), for storing the key somewhere you trust. |
| `x25519PublicKey` | value | `(-> X25519SecretKey X25519PublicKey)` | `Alloc,Mut` |  | The public key of `k`. |
| `x25519PublicKeyFromBytes` | value | `(-> String (Result X25519PublicKey Error))` | `Alloc,Mut` |  | A public key from its 32 bytes. Every 32-byte string is accepted (RFC 7748, section 5); any other length is `cryptoInvalidLength`. |
| `x25519PublicKeyBytes` | value | `(-> X25519PublicKey String)` |  |  | The 32 bytes of a public key. |
| `x25519` | value | `(-> X25519SecretKey X25519PublicKey (Result SecretBytes Error))` | `Alloc,IO,Mut,Unsafe` |  | The shared secret X25519(k, pk), as `SecretBytes`. `Err` with `cryptoInvalidKey` when it is all zero (the peer sent a point of small order), and `cryptoInvalidLength` when `pk` is not 32 bytes. |

## `Err`

`stdlib/Err.ax` — 37 public names

Err — Axiom's failure type, its error record, the combinators that
work on them, and checked integer arithmetic.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Result` | data |  |  |  | Success or failure: `(Ok x)` carries the answer and `(Err e)` the error. Library functions answer it instead of a sentinel; take it apart with `match`, or unwrap it with `?` inside a function that answers a `Result` itself. |
| `Error` | struct |  |  |  | What a failing library call answers inside `Err`: a stable numeric `code` (the `err*` constants), a `message` for a person, and the `context` later callers add with `withContext`. |
| `errDivideByZero` | value | `Int` |  |  | A zero divisor, from `divChecked` and `remChecked`. |
| `errOverflow` | value | `Int` |  |  | A result the 64-bit integer cannot hold. |
| `errShiftTooWide` | value | `Int` |  |  | A shift amount below 0, or of 64 or more. |
| `errShortWrite` | value | `Int` |  |  | A descriptor accepted some bytes and then accepted none, without an errno to say why: `write` answered 0, which the kernel doesn't count as an error, but the bytes were meant to go and did not (`ERR-REC-3`). |
| `errUnexpectedEof` | value | `Int` |  |  | The input ended before the bytes a reader was asked for, as when a peer closes in the middle of `Net.tcpReadExact`. |
| `errInvalidData` | value | `Int` |  |  | Bytes arrived that break the shape the reader expects, as when a line runs past the limit `Net.tcpReadLine` was given. |
| `mkError` | value | `(-> Int String Error)` | `Alloc` |  | An `Error` with `code` and `message` and no context yet. |
| `errCode` | value | `(-> Error Int)` |  |  | The error's numeric code, one of the `err*` constants. |
| `errMessage` | value | `(-> Error String)` |  |  | The error's message. |
| `errContext` | value | `(-> Error String)` |  |  | The context callers added with `withContext`, or empty. |
| `errorText` | value | `(-> Error String)` | `Alloc,Mut` |  | The error as one line of text: what `main` writes to standard error when it answers `Err` (ERR-REC-4), and what a longer report is built from. |
| `isOk` | value | `(-> (Result a e) Bool)` |  |  | Whether the result is `Ok`. |
| `isErr` | value | `(-> (Result a e) Bool)` |  |  | Whether the result is `Err`. |
| `unwrapOr` | value | `(-> (Result a e) a a)` |  |  | The `Ok` value, or `fallback` when the result is `Err`. |
| `mapOk` | value | `(-> (Result a e) (-> a b) (Result b e))` | `Alloc (incomplete)` |  | Apply `f` to the `Ok` value; an `Err` passes through unchanged. |
| `mapErr` | value | `(-> (Result a e) (-> e f) (Result a f))` | `Alloc (incomplete)` |  | Apply `f` to the `Err` value; an `Ok` passes through unchanged. |
| `andThen` | value | `(-> (Result a e) (-> a (Result b e)) (Result b e))` | `Alloc (incomplete)` |  | Chain a fallible step: apply `f` to the `Ok` value and answer its result; an `Err` passes through unchanged. |
| `errContextOf` | value | `(-> Error String Error)` | `Alloc` |  | `e` with its context set to `ctx`, so a caller up the stack can say what it was doing when the error arrived: `(errContextOf e "axqOpen")`. `withContext` does the same to the error inside a `Result`. |
| `withContext` | value | `(-> (Result a Error) String (Result a Error))` | `Alloc` |  | Set the context of the error inside `r` to `ctx`, so a caller up the stack can say what it was doing. An `Ok` passes through unchanged. |
| `okOr` | value | `(-> (Option a) e (Result a e))` | `Alloc` |  | Turn an `Option` into a `Result`: `Some` becomes `Ok`, and `None` becomes `Err e`. |
| `toOption` | value | `(-> (Result a e) (Option a))` | `Alloc` |  | Turn a `Result` into an `Option`: `Ok` becomes `Some`, and `Err` becomes `None`, dropping the error. |
| `isSome` | value | `(-> (Option a) Bool)` |  |  | Whether the `Option` holds a value. The `Option` half of `isOk`. |
| `isNone` | value | `(-> (Option a) Bool)` |  |  | Whether the `Option` is empty: `isSome` negated. |
| `optUnwrapOr` | value | `(-> (Option a) a a)` |  |  | The value, or `fallback` when there is none. |
| `optMap` | value | `(-> (Option a) (-> a b) (Option b))` | `Alloc (incomplete)` |  | Apply `f` to the value if there is one, leaving an absence alone. The result type is `f`'s, so this is how an `(Option Int)` becomes an `(Option String)`. |
| `optAndThen` | value | `(-> (Option a) (-> a (Option b)) (Option b))` | `incomplete` |  | Chain a step that may itself be absent, without nesting two `Option`s. `optMap` with a function answering `(Option b)` would give `(Option (Option b))`; this is that flattened. |
| `optOr` | value | `(-> (Option a) (Option a) (Option a))` | `Alloc` |  | The first of two that is present. `alt` is evaluated at the call, even when `o` holds a value, so a caller whose alternative is expensive should write the `match`. |
| `intMin` | value | `Int` |  |  | The smallest `Int`, -9223372036854775808. |
| `addChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | `a + b`, or `Err` with `errOverflow` when the sum does not fit an `Int`. |
| `subChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | `a - b`, or `Err` with `errOverflow` when the difference does not fit an `Int`. |
| `mulChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | `a * b`, or `Err` with `errOverflow` when the product does not fit an `Int`. |
| `divChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | `a / b` truncated toward zero, or `Err` with `errDivideByZero` for a zero divisor and `errOverflow` for `intMin / -1`. |
| `remChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | The remainder of `a / b`, or `Err` with `errDivideByZero` for a zero divisor. |
| `shlChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | `a << n`, or `Err` with `errShiftTooWide` when `n` is negative or 64 or more, where the `<<` operator traps (exit 84, MM-VAL-3b). |
| `shrChecked` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | `a >> n`, or `Err` with `errShiftTooWide` when `n` is negative or 64 or more. |

## `Fallible`

`stdlib/Fallible.ax` — 9 public names

Fallible - the effect a batch loop's deep callee performs on a
malformed record, and the handlers that answer it without unwinding.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Fallible` | effect |  |  |  | The effect a deep callee performs on a malformed record: `(fallibleMalformed reason)` asks the nearest handler what to do, and the handler's answer is the operation's result, so the batch loop decides without the callee unwinding. |
| `fallibleSkipped` | value | `Int` |  |  | The value a handler answers to mean "skip this record": the most negative `Int`. A loop compares the value it got against this, or asks `fallibleIsSkipped`. |
| `fallibleIsSkipped` | value | `(-> Int Bool)` |  |  | Whether a value is the skip sentinel. The comparison a batch loop makes once per record; it allocates nothing. |
| `fallibleSkip` | value | `(-> String Int)` |  |  | Skip every malformed record: answer `fallibleSkipped`, whatever the message. A one-parameter top-level function is a value, so it is passed bare. |
| `fallibleDefault` | value | `(-> Int String Int)` | `Alloc` |  | Use `d` in place of every malformed record: `(fallibleDefault 0)` is the handler. |
| `FallibleTally` | struct |  |  |  | How many records were malformed, as `fallibleCounting` counts them. |
| `fallibleTally` | value | `FallibleTally` | `Alloc` |  | A fresh tally at zero. |
| `fallibleCount` | value | `(-> FallibleTally Int)` |  |  | What a tally holds. |
| `fallibleCounting` | value | `(-> FallibleTally (-> String Int) String Int)` | `Alloc,Mut` |  | Count every malformed record in `tally`, then answer as `next` would: `(fallibleCounting t fallibleSkip)` skips and counts, `(fallibleCounting t (fallibleDefault 0))` substitutes and counts. The `handle` installing it lists `Mut` beside `Fallible`, because a handler's own effects count at the site that installs it. |

## `Float`

`stdlib/Float.ax` — 14 public names

Float - IEEE 754 binary64 values, exact integer conversions, and
text that reads back to exactly the same value.

    (floatToString 0.1)              ; "0.1"
    (floatToString (/ 1.0 3.0))      ; "0.3333333333333333"
    (floatToString 1e22)             ; "1e+22"
    (floatParse "2.5e-3")            ; (Ok 0.0025)
    (floatToBits 1.0)                ; 4607182418800017408

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `floatToBits` | value | `(-> Float Int)` |  |  | The bits of `x`, sign first: the IEEE 754 binary64 encoding read as an `Int`. `(floatToBits 1.0)` is 4607182418800017408 and `(floatToBits -0.0)` is the most negative `Int`. |
| `floatFromBits` | value | `(-> Int Float)` |  |  | The `Float` whose IEEE 754 binary64 encoding is `n`. Every `Int` is some `Float`, including the infinities and every NaN payload. |
| `floatInfinity` | value | `Float` |  |  | Positive infinity. |
| `floatNan` | value | `Float` |  |  | The quiet NaN `floatParse` answers for "nan". |
| `floatIsNan` | value | `(-> Float Bool)` |  |  | True for every NaN, whatever its sign and payload. |
| `floatIsInfinite` | value | `(-> Float Bool)` |  |  | True for positive and negative infinity. |
| `floatIsFinite` | value | `(-> Float Bool)` |  |  | True for every value that is neither an infinity nor a NaN. |
| `floatParseFailed` | value | `Int` |  |  | Text that isn't a number `floatParse` reads. |
| `floatConversionFailed` | value | `Int` |  |  | An integer conversion that would round, discard a fraction, or leave the signed 64-bit range. Non-finite values fail too. |
| `floatFromIntExact` | value | `(-> Int (Result Float Error))` | `Alloc` |  | Convert `n` to `Float` when binary64 represents its value exactly. A rounded integer answers `Err` with code `floatConversionFailed`. |
| `floatToIntExact` | value | `(-> Float (Result Int Error))` | `Alloc` |  | Convert a finite, integral `x` in the signed 64-bit range to `Int`. Both signed zeros answer zero. Fractions, infinities, NaNs and values outside the range answer `Err` with `floatConversionFailed`. |
| `floatParse` | value | `(-> String (Result Float Error))` | `Alloc,Mut` |  | The number that `s` spells, correctly rounded to the nearest binary64, ties to even. See the module comment for the syntax. |
| `floatToString` | value | `(-> Float String)` | `Alloc,Mut` |  | The shortest text that `floatParse` reads back to exactly `x`, in Python's `repr` format: `0.1`, `2.0`, `1e+22`, `-0.0`, `inf`, `nan`. |
| `floatToFixed` | value | `(-> Float Int String)` | `Alloc,Mut` | `;@axiom:pre((<= places 4096))` | `x` with `places` decimal places, rounded from its exact binary64 value, with halfway cases away from zero. Negative precision means zero places. Precision above 4096 traps before allocating output. Special values render as `inf`, `-inf` and `nan`; signed zero keeps its sign. The integer part has no Int-sized bound. |

## `Fmt`

`stdlib/Fmt.ax` — 11 public names

Fmt - number formatting, in Axiom.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `fmtIntWidth` | value | `(-> Int Int)` |  |  | Decimal digits in `n`, counting a leading `-` and treating 0 as one digit. |
| `fmtInt` | value | `(-> Int String)` | `Alloc,Mut` |  | `n` in base 10 as a `Str`. |
| `fmtUIntWord` | value | `(-> Int String)` | `Alloc,Mut` |  | Format a word's bits as an unsigned decimal integer. `format` uses this for fixed-width unsigned values through their word representation. |
| `fmtHex` | value | `(-> Int String)` | `Alloc,Mut` |  | `n` in lowercase hexadecimal with no prefix, such as `ff` for 255. A negative number is written as its two's-complement 64-bit word. |
| `fmtPadLeft` | value | `(-> String Int String)` | `Alloc,Mut` |  | `s` padded on the left with spaces to at least `width` bytes. |
| `fmtPadRight` | value | `(-> String Int String)` | `Alloc,Mut` |  | `s` padded on the right with spaces to at least `width` bytes. |
| `fmtPadCenter` | value | `(-> String Int String)` | `Alloc,Mut` |  | `s` centred in `width` bytes, with an odd remainder on the right, as Rust's `{:^}` does. |
| `fmtPadZerosLeft` | value | `(-> String Int String)` | `Alloc,Mut,Unsafe` |  | `s` padded on the left with zeros to at least `width` bytes, keeping a leading sign in front of them: `-7` at width 4 is `-007`. This is the `{n:04}` specifier. |
| `fmtHexUpper` | value | `(-> Int String)` | `Alloc,Mut` |  | `n` in uppercase hexadecimal with no prefix, such as `FF` for 255: the `{n:X}` specifier. |
| `fmtFloat` | value | `(-> Float String)` | `Alloc,Mut` |  | `x` with six decimal places. |
| `fmtFloatPrec` | value | `(-> Float Int String)` | `Alloc,Mut` |  | `x` with `places` decimal places, rounded from its exact binary64 value, halfway cases away from zero. Negative precision means zero; values above 4096 trap. The integer part covers every finite Float. |

## `IO`

`stdlib/IO.ax` — 73 public names

IO - files, standard streams, terminals, readiness and sockets.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `File` | struct |  |  |  | An open file, socket or standard stream. Aliases share it; the last share closes the descriptor, and `fileClose` closes it early for every alias. |
| `stdin` | value | `File` | `Alloc,IO` |  | The process's standard input as a `File`. Like `stdout` and `stderr`, it never closes its descriptor: `fileClose stdin` retires that one value and leaves the process's stream open. |
| `stdout` | value | `File` | `Alloc,IO` |  | The process's standard output as a `File`, for `fileWrite` and friends. One shared owner: it is never closed by scope. |
| `stderr` | value | `File` | `Alloc,IO` |  | The process's standard error as a `File`. One shared owner: it is never closed by scope. |
| `nullDevice` | value | `String` |  |  | The path of the null device, for `openPath`: `/dev/null`, or `NUL` on Windows. A read from it is at the end of the file at once, a write to it keeps nothing, and it is never a terminal. |
| `fileClose` | value | `(-> File (Result Int Error))` | `Alloc,IO,Unsafe` |  | Close early, once: `(Ok 0)`, or `(Err e)` carrying the errno of the close - on a written file, where a deferred write error surfaces. Aliases observe the close, and any later use of one traps 85. The descriptor is retired before the close and the close is never retried. Closing a standard stream retires that value only. |
| `ErrorKind` | data |  |  |  | What went wrong, in words that mean the same on every target. An `Error`'s code is the kernel's errno, and those numbers differ: EAGAIN is 11 on Linux and 35 on Darwin. Match on `(errorKind e)` instead of a number. The names are `std::io::ErrorKind`'s. |
| `errorKind` | value | `(-> Error ErrorKind)` |  |  | The kind of failure `e` reports. Errno numbers that are the same on every target are written here; the rest come from `Sys.Platform`. The library's own `errUnexpectedEof` and `errInvalidData` have kinds too, and any other code, including a program's own, is `Other`. |
| `writeStr` | value | `(-> File String Int)` | `Alloc,IO` |  | Write all of `s` to `f`, returning the number of bytes written or a negative errno. This is the printing path's answer: `println` is `(writeStr stdout ...)`, and a statement that prints does not have to bind a `Result`. `fileWrite` answers the same write as a `Result`. |
| `writeSlice` | value | `(-> File String Int Int Int)` | `Alloc,IO` |  | Write the `len` bytes of `s` that start at byte `start`, all of them, returning the number written or a negative errno - `writeStr` over a part of a string, with no copy. |
| `writeOut` | value | `(-> String Int)` | `Alloc,IO` |  | Write all of `s` to standard output, or to standard error: the bytes written, or a negative errno. `println` and `eprintln` are these with the line built at expansion time. They make no `File`, so printing allocates nothing on the way out; `(writeStr stdout s)` is the same write through a `File`. |
| `writeErr` | value | `(-> String Int)` | `Alloc,IO` |  | Write `s` to standard error, with no newline added. Answers the number of bytes written. |
| `fileWrite` | value | `(-> File String (Result Int Error))` | `Alloc,IO` |  | Write every byte of `s` to `f`: `(Ok n)`, or `(Err e)` whose code is the errno of the write that failed. |
| `println` | macro |  |  |  | Print to standard output with a newline. A string literal's `{name}` holes interpolate the bindings they name, as in `(println "hello, {name}")`; any other argument is rendered, so `(println n)` prints an `Int`. |
| `eprintln` | macro |  |  |  | Print to standard error with a newline, with the same holes as `println`. |
| `readFile` | value | `(-> String (Result String Error))` | `Alloc,IO,Mut` |  | The whole contents of the file at `path`: `(Ok text)`, or `(Err e)` whose code is the errno, its message `readFile: PATH: errno N`. A missing file is ENOENT, 2, and a directory is EISDIR, 21. An empty file is `(Ok "")`. |
| `writeFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` |  | Write `s` to `path`, creating it or truncating what is there. Answers `(Ok bytes)`, or `(Err e)` whose code is the errno. |
| `appendFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` |  | Add `s` to the end of `path`, creating it if absent. Answers `(Ok bytes)`, or `(Err e)` whose code is the errno. `O_APPEND` makes the seek and the write one operation, so two processes appending to one log interleave whole writes. |
| `removeFile` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` |  | Remove the file `path`. Answers `(Ok 0)`, or `(Err …)` carrying the errno. It does not remove a directory; that is `removeDir`. |
| `renamePath` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` |  | Move `old` to `new`, answering `(Ok 0)` or `(Err …)` with the errno. |
| `openPath` | value | `(-> String Int (Result File Error))` | `Alloc,IO,Mut` |  | Open `path` with `flags` (`oRdonly`, `oWronlyCreateTrunc`, ...): `(Ok file)`, or `(Err e)` whose code is the errno. New files get mode 0644. The file closes when its last owner leaves scope. |
| `copyFile` | value | `(-> String String (Result Int Error))` | `Alloc,IO,Mut` |  | Copy `src` onto `dst`, answering `(Ok bytes)` or `(Err e)`. `dst` is created or truncated, and left alone when `src` can't be read. |
| `fileExists` | value | `(-> String Bool)` | `Alloc,IO,Mut` |  | True when `path` names something that can be opened for reading - a directory included. `isDir` separates them. |
| `isDir` | value | `(-> String Bool)` | `Alloc,IO,Mut` |  | True when `path` names a directory: one that opens and whose read answers EISDIR. An empty file answers false. |
| `fileSize` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` |  | The size of `path` in bytes, or `(Err …)` carrying the errno. It seeks to the end, which is what the size is. |
| `makeDir` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` |  | Create the directory `path`, mode 0755. Answers `(Ok 0)`, or `(Err …)` carrying the errno - `EEXIST` when it is already there. |
| `makeDirMode` | value | `(-> String Int (Result Int Error))` | `Alloc,IO,Mut` |  | Create the directory `path` with the permission bits `mode`, such as 448 (0700) for a directory only its owner may enter. Answers `(Ok 0)`, or `(Err e)`. |
| `makeDirAll` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` |  | Create `path` and every missing directory above it. Answers `(Ok 0)`, or `(Err …)` carrying the errno of the first component that could not be made. |
| `removeDir` | value | `(-> String (Result Int Error))` | `Alloc,IO,Mut` |  | Remove the empty directory `path`. Answers `(Ok 0)`, or `(Err …)` - `ENOTEMPTY` when it still holds entries. Nothing here removes a tree: that is a loop over `listDir`, and it is the caller's to write. |
| `listDir` | value | `(-> String (Result (Vec String) Error))` | `Alloc,IO,Mut` |  | The entries of the directory `path`, sorted by byte, with `.` and `..` removed: `(Ok names)`, or `(Err e)` whose code is the errno. A missing path is ENOENT, 2, and a file is ENOTDIR, 20. |
| `cwd` | value | `(Result String Error)` | `Alloc,IO,Mut` |  | The process's working directory as an absolute path: `(Ok path)`, or `(Err e)` whose code is the errno. |
| `exit` | value | `(-> Int Int)` | `IO` |  | End the process with status `code`, running no further code. |
| `die` | value | `(-> String Int Int)` | `Alloc,IO,Mut` |  | Print `s` to standard error and exit with `code`. Never returns. |
| `todo` | value | `(-> String a)` | `Alloc,IO,Mut` |  | Exit 70 with `todo: <what>` on standard error; types as any result and never returns. |
| `readLine` | value | `(-> File (Result (Option String) Error))` | `Alloc,IO,Mut` |  | One line of `f` without its newline: `(Ok (Some line))`; `(Ok None)` at end of input when nothing was read; `(Err e)` whose code is the errno, its message `readLine: errno 9`. |
| `readAll` | value | `(-> File (Result String Error))` | `Alloc,IO,Mut` |  | Everything left on `f` to end of input: `(Ok s)`, `(Ok "")` when nothing arrived, or `(Err e)` whose code is the errno. |
| `ReadBuffer` | struct |  |  |  | Mutable input storage. The constructor and backing string stay private, so safe code cannot alias an immutable String as a writable buffer. |
| `readBufferNew` | value | `(-> Int ReadBuffer)` | `Alloc,Mut` |  | Allocate a zeroed input buffer of n bytes. A negative size traps 77. |
| `readBufferLen` | value | `(-> ReadBuffer Int)` |  |  | The buffer's capacity, in bytes. |
| `readBufferByte` | value | `(-> ReadBuffer Int Int)` |  |  | Read one byte, with the same bounds check as strByte. |
| `readBufferText` | value | `(-> ReadBuffer Int Int String)` | `Alloc,Mut` |  | Copy a checked range into an immutable String. Later reads into the buffer do not change the returned bytes. |
| `readBufferPut` | value | `(-> ReadBuffer Int String Int)` | `Mut` |  | Copy `text` into `buf` from byte `at`, answering how many bytes it copied, `strLen text`. A range outside `buf` stops the program with status 77, as `fileRead`'s does. |
| `fileRead` | value | `(-> File ReadBuffer Int Int (Result Int Error))` | `Alloc,IO,Mut` |  | Read at most `count` bytes from `f` into `buf[at .. at + count)`: `(Ok n)`, `(Ok 0)` at end of input, or `(Err e)`. A range outside `buf` stops the program with status 77 before the kernel sees it. A ReadBuffer cannot be captured by a parallel binding; its bytes are used by one binding at a time. |
| `TermSize` | struct |  |  |  | A terminal's size in character cells. A terminal that was never sized reports 0 for both; treat 0 as unknown and fall back to 80x24. |
| `TermGuard` | struct |  |  |  | A terminal in raw mode, and what it was before. Releasing the last share restores it. |
| `isTerminal` | value | `(-> File Bool)` | `Alloc,IO,Mut` |  | True when `f` is a terminal: it has terminal attributes to read, which is what libc's `isatty` asks too. A pipe, a file or a socket answers false, and so does every file on a target without `termios`. |
| `termSize` | value | `(-> File (Result TermSize Error))` | `Alloc,IO,Mut` |  | The size of the terminal on `f`: `(Ok size)`, or `(Err e)` with the kernel's errno when `f` is not one, ENOTTY for a pipe or a file. A terminal may answer 0 rows and 0 columns; treat 0 as unknown. |
| `termRaw` | value | `(-> File Bool (Result TermGuard Error))` | `Alloc,IO,Mut,Unsafe` |  | Put the terminal on `f` into raw mode, saving what it was first: `(Ok guard)`, or `(Err e)` with the kernel's errno, ENOTTY for a pipe or a file. With `keepSignals` true, ^C still raises SIGINT; with false it arrives as byte 3. Releasing the guard, or `termRestore`, puts it back. |
| `termRestore` | value | `(-> TermGuard (Result Int Error))` | `Alloc,IO,Unsafe` |  | Put the terminal back as `termRaw` found it, now rather than when the guard's last share goes: `(Ok 0)`, or `(Err e)`. A second call answers `(Ok 0)` and does nothing. |
| `Poller` | struct |  |  |  | The readiness poller `stdin` and the socket calls share: one owned poll set, so two parts of a program cannot register the same descriptor twice. |
| `pollerNew` | value | `(-> Int (Result Poller Error))` | `Alloc,IO,Mut,Unsafe` | `;@axiom:pre((> cap 0))` | A poller that answers at most `cap` events per wait: `(Ok p)`, or `(Err e)` carrying the errno - EMFILE when the process has no descriptor left. |
| `pollerAdd` | value | `(-> Poller File Int (Result Int Error))` | `Alloc,IO,Mut` |  | Watch `f` for readability under `token`: `(Ok 0)`, or `(Err e)`. The poller does not keep `f` alive; close it, or let it go, and its registration goes with it. |
| `pollerRemove` | value | `(-> Poller File (Result Int Error))` | `Alloc,IO,Mut` |  | Stop watching `f`: `(Ok 0)`, or `(Err e)` - ENOENT when it was not being watched. |
| `pollerAddSignals` | value | `(-> Poller Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Watch the signals in `mask` (bit N-1 for signal N, `Sys.sysSigBit`) under `token`: `(Ok 0)`, or `(Err e)`. Block them with `Sys.sysSignalBlock` first. `pollerSignal` reads which one arrived. Windows supports `Sys.Platform.sigInt` and `sigBreak`: other bits answer `Err` 78. One table row holds the mask; 0 removes it. The process mask persists after removal or close, and competing pollers consume each pending control once between them. |
| `pollerWait` | value | `(-> Poller Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Wait for readiness: `(Ok n)` with `n` events to read with `pollerToken` and `pollerSignal`, `(Ok 0)` when `timeoutMs` passed first, or `(Err e)`. A negative `timeoutMs` waits for ever; 0 asks and answers at once. EINTR answers `(Ok 0)`: nothing was collected. |
| `pollerToken` | value | `(-> Poller Int Int)` |  |  | The token event `i` of the last wait carries. An `i` outside the events that wait answered stops the program with status 77. |
| `pollerSignal` | value | `(-> Poller Int (Option Int))` | `Alloc,IO` |  | The signal event `i` of the last wait delivered, or `None` when it is not a signal. On Linux this reads the signal descriptor, once per event. Windows records one console control in the event, so reading it again answers the same number. An `i` outside the last wait's events stops the program with status 77. |
| `pollerClose` | value | `(-> Poller (Result Int Error))` | `Alloc,IO,Unsafe` |  | Close the poller now rather than at its last share: `(Ok 0)`, or `(Err e)`. Any later use traps 85. |
| `socketOpen` | value | `(-> String (Result File Error))` | `Alloc,IO,Mut,Unsafe` |  | A blocking TCP socket for the family of `addr`, not yet bound or connected: `(Ok file)`, or `(Err e)`. |
| `socketBind` | value | `(-> File String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Bind `s` to `addr`. The length comes from the family in the address. |
| `socketListen` | value | `(-> File Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Listen on a bound socket, queueing up to `backlog` connections. |
| `socketAccept` | value | `(-> File (Result File Error))` | `Alloc,IO,Mut,Unsafe` |  | The next connection on a listening socket, as a blocking socket of its own: `(Ok file)`, or `(Err e)` - EAGAIN when the listener does not block and nothing is waiting. The accepted socket blocks whatever the listener's mode, on every target. |
| `socketConnect` | value | `(-> File String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Connect `s` to `addr`. A non-blocking socket answers `(Err e)` with EINPROGRESS, which is the kernel's contract rather than a failure. |
| `socketShutdown` | value | `(-> File Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Close one or both halves: `how` is 0 for reading, 1 for writing and 2 for both. Anything else is EINVAL. |
| `socketSetInt` | value | `(-> File Int Int Int (Result Int Error))` | `Alloc,IO,Mut` |  | Set an integer socket option, such as `soReuseAddr` at `solSocket` or `tcpNoDelayOpt` at `ipprotoTcp`. |
| `socketSetTimeout` | value | `(-> File Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Set the `soRcvTimeo` or `soSndTimeo` timeout, in microseconds; 0 waits for ever and a negative timeout is EINVAL. |
| `socketAddr` | value | `(-> File Bool (Result String Error))` | `Alloc,IO,Mut,Unsafe` |  | The address `s` is bound to, or with `peer` true the address of the peer it is connected to, as `netAddrMaxBytes` bytes. |
| `socketSend` | value | `(-> File String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Send all of `data`, continuing after a short send and retrying EINTR: `(Ok n)`, or `(Err e)` - EPIPE when the peer has closed, never a signal. |
| `socketSendSome` | value | `(-> File String (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | One send of as much of `data` as the socket takes now, retrying EINTR: `(Ok n)`, where `n` can be short of `strLen data`, or `(Err e)` - EAGAIN when a non-blocking socket took nothing, EPIPE when the peer has closed. Unlike `socketSend`, a short send loses no count. |
| `socketGetInt` | value | `(-> File Int Int (Result Int Error))` | `Alloc,IO,Mut` |  | Read an integer option: `(Ok value)`, or `(Err e)`. |
| `socketGetTimeout` | value | `(-> File Int (Result Int Error))` | `Alloc,IO,Mut` |  | Read the `soRcvTimeo` or `soSndTimeo` timeout in microseconds, 0 when reads or writes wait for ever. |
| `socketConnectWithin` | value | `(-> File String Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Connect `s` to `addr`, waiting at most `ms` milliseconds: `(Ok 0)`, or `(Err e)` - ETIMEDOUT when the time ran out first, or the connect's own error. The connect runs non-blocking under a one-slot poller that waits for the socket to become writable; the socket is blocking again on every answer. |
| `fileSetNonBlocking` | value | `(-> File Bool (Result Int Error))` | `Alloc,IO,Mut` |  | Switch `f` between blocking (`false`) and non-blocking (`true`), keeping its other flags. A read or write that cannot proceed on a non-blocking file answers `(Err e)` whose `errorKind` is `WouldBlock`. |

## `Intern`

`stdlib/Intern.ax` — 12 public names

Intern - a string interner, in Axiom.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `internSlotOf` | value | `(-> String Int Int)` |  |  | The slot `s` probes first, in [0, cap). |
| `InternState` | struct |  |  |  | An owning interner. Its raw handle is borrowed through `internWordOf`. Keep this owner alive while that handle is used. |
| `internNew` | value | `Int` | `Alloc,Mut` |  | An empty interner with `internDefaultCap` slots. |
| `internNewTyped` | value | `InternState` | `Alloc,Mut` |  | An empty owning interner with `internDefaultCap` slots. Scope cleanup releases its strings and slot allocation. |
| `internWordOf` | value | `(-> InternState Int)` |  |  | Borrow the raw handle of a live owning interner. The returned word remains valid only while `owner` is alive. It carries no ownership share; do not pass it to `internFree`. |
| `internWithCapacity` | value | `(-> Int Int)` | `Alloc,Mut` |  | An interner sized so `want` distinct strings fit without rehashing. |
| `internFree` | value | `(-> Int Int)` | `Unsafe` |  | Hand `it` back: the slot table, the `Vec`, and one share of every string in it. Answers 0. `it` must be a live interner owning this share. Its raw Int handle and any unretained views into it must not be used after release. |
| `internCap` | value | `(-> Int Int)` |  |  | How many strings the table can hold before it grows. |
| `internCount` | value | `(-> Int Int)` |  |  | How many distinct strings have been interned. Ids are exactly 0..internCount-1, with no gaps - that is what "dense" means here, and it is what lets a caller size a side table by `internCount` and index it by id. |
| `internLookup` | value | `(-> Int Int String)` | `Alloc,Mut` |  | The string with id `id`, or an empty `Str` if `id` was never handed out. |
| `internFind` | value | `(-> Int String (Option Int))` |  |  | The id of a string equal in content to `s`, or `None`. |
| `internIntern` | value | `(-> Int String Int)` | `Alloc,Mut` |  | The id for `s`, interning it if its content is new. |

## `Cereal`

`stdlib/Cereal.ax` — 50 public names

Cereal — typed serialisation for JSON, TOML and YAML.
Codecs share CerealValue and return Result with explicit resource limits.
The json* functions retain the raw-handle migration API for JSON-RPC.
Raw consumers require live Cereal handles; new code uses typed values.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `jsonNull` | value | `Int` | `Alloc,Mut` |  | The JSON `null` value. |
| `jsonBool` | value | `(-> Int Int)` | `Alloc,Mut` |  | A JSON boolean: `true` for a non-zero `b`, `false` for 0. |
| `jsonNum` | value | `(-> Int Int)` | `Alloc,Mut` |  | A number from an integer. The raw text is rendered from the value, so `jsonNumText` is total for constructed values as well as parsed ones. |
| `jsonStr` | value | `(-> String Int)` | `Alloc,Mut` |  | A JSON string holding `s`. |
| `jsonArr` | value | `Int` | `Alloc,Mut` |  | An empty JSON array; add to it with `jsonArrPush`. |
| `jsonObj` | value | `Int` | `Alloc,Mut` |  | An empty JSON object; add to it with `jsonObjPut`. |
| `jsonIsNull` | value | `(-> Int Bool)` |  |  | Whether the value is JSON `null`. |
| `jsonBoolVal` | value | `(-> Int Int)` |  |  | A JSON boolean as 1 or 0, and 0 for any other value. |
| `jsonInt` | value | `(-> Int Int)` |  |  | The integer value of a number, and 0 for any other value. Test `jsonTag` first when 0 must mean the number. |
| `jsonNumText` | value | `(-> Int String)` |  |  | A JSON number as the text it was written with, and empty for any other value. |
| `jsonStrVal` | value | `(-> Int String)` |  |  | A JSON string's text, and empty for any other value. |
| `jsonArrLen` | value | `(-> Int Int)` |  |  | How many elements a JSON array holds, and 0 for any other value. |
| `jsonArrGet` | value | `(-> Int Int Int)` |  |  | Element `i` of a JSON array, or JSON `null` when `v` is not an array or `i` is out of range. |
| `jsonArrPush` | value | `(-> Int Int Int)` | `Alloc,Mut` |  | Append `x` to a JSON array. Any other value is left alone. Answers `v`. |
| `jsonObjLen` | value | `(-> Int Int)` |  |  | How many members a JSON object holds, and 0 for any other value. |
| `jsonObjPut` | value | `(-> Int String Int Int)` | `Alloc,Mut` |  | Add the member `key` with value `x` to a JSON object. A repeated key is appended, not replaced, and `jsonGet` answers the first. |
| `jsonGet` | value | `(-> Int String Int)` |  |  | The value under `key` in a JSON object, or 0 when there is none. `jsonIsNull` answers true for both, so compare against 0 to tell an absent member from one set to `null`. |
| `jsonFind` | value | `(-> Int String (Option Int))` | `Alloc` |  | The value under `key` in a JSON object. `None` means the key is absent or the value is not an object; `Some jsonNull` means explicit `null`. A repeated key returns its first member. |
| `jsonGetInt` | value | `(-> Int String Int)` |  |  | The integer under `key` in a JSON object, or 0 when the key is absent or not a number. |
| `jsonGetStr` | value | `(-> Int String String)` |  |  | The string under `key` in a JSON object, or empty when the key is absent or not a string. |
| `jsonWrite` | value | `(-> Int String)` | `Alloc,Mut` |  | The value as JSON text, on one line with no spaces, strings escaped as JSON requires. |
| `jsonParse` | value | `(-> String Int)` | `Alloc,Mut` |  | Parse a whole document: one value, then nothing but whitespace. Answers 0 on any error, which is why every accessor tolerates 0. |
| `CerealValue` | data |  |  |  | A parsed document from any of the three formats: null, a boolean, an integer, a float, text, a list or an object of `CerealMember`s. |
| `CerealMember` | struct |  |  |  | One `key: value` member of a `CObject`. |
| `CerealFormat` | data |  |  |  | Which text format to read or write: JSON, TOML or YAML. |
| `CerealLimits` | struct |  |  |  | What a parse may cost: the nesting `depth`, the input `bytes` and the `nodes` it may build. Past any of them the parse answers `Err` instead of running on. |
| `Codec` | data |  |  |  | A codec converts application values to the common tree and back. Compose these functions for records; no raw reference words cross this interface, and a missing or wrongly typed field is an Error. |
| `cerealLimits` | value | `CerealLimits` | `Alloc` |  | The default limits: depth 64, one MiB of input, 100000 nodes. |
| `cerealObjectGet` | value | `(-> CerealValue String (Option CerealValue))` | `Alloc` |  | The member under `key` of a `CObject`, or `None` when the key is absent or the value is not an object. |
| `cerealRequired` | value | `(-> CerealValue String (Result CerealValue Error))` | `Alloc,Mut` |  | The member under `key` of a `CObject`, or `Err` naming the missing key. |
| `cerealInt` | value | `(-> CerealValue (Result Int Error))` | `Alloc,Mut` |  | The `CInt` inside, or `Err` when the value is not an integer. |
| `cerealText` | value | `(-> CerealValue (Result String Error))` | `Alloc,Mut` |  | The `CText` inside, or `Err` when the value is not text. |
| `cerealBool` | value | `(-> CerealValue (Result Bool Error))` | `Alloc,Mut` |  | The `CBool` inside, or `Err` when the value is not a boolean. |
| `cerealIntCodec` | value | `(Codec Int)` | `Alloc,Mut` |  | The `Codec` that reads and writes an `Int`. |
| `cerealTextCodec` | value | `(Codec String)` | `Alloc,Mut` |  | The `Codec` that reads and writes a `String`. |
| `cerealBoolCodec` | value | `(Codec Bool)` | `Alloc,Mut` |  | The `Codec` that reads and writes a `Bool`. |
| `cerealValueCodec` | value | `(Codec CerealValue)` | `Alloc` |  | The `Codec` that passes a `CerealValue` through unchanged, for a field you want to keep as a tree. |
| `cerealToValue` | value | `(-> (Codec a) a (Result CerealValue Error))` | `incomplete` |  | Encode `value` with the codec into a `CerealValue` tree. |
| `cerealFromValue` | value | `(-> (Codec a) CerealValue (Result a Error))` | `incomplete` |  | Decode a `CerealValue` tree with the codec. |
| `cerealVecCodec` | value | `(-> (Codec a) (Codec (Vec a)))` | `Alloc,Mut (incomplete)` |  | The `Codec` for a `Vec` of what `codec` handles, as a list. |
| `cerealOptionCodec` | value | `(-> (Codec a) (Codec (Option a)))` | `Alloc (incomplete)` |  | The `Codec` for an `Option` of what `codec` handles: `None` is null. |
| `cerealField` | value | `(-> (Codec a) CerealValue String (Result a Error))` | `Alloc,Mut (incomplete)` |  | Include the field name in a record codec's error context. |
| `cerealEncodeWith` | value | `(-> CerealFormat CerealLimits CerealValue (Result String Error))` | `Alloc,Mut` |  | Write a `CerealValue` tree in `format` under the given limits. Invalid limits answer `Err`. |
| `cerealEncode` | value | `(-> CerealFormat CerealValue (Result String Error))` | `Alloc,Mut` |  | Write a `CerealValue` tree in `format` under the default limits. |
| `cerealDecodeWith` | value | `(-> CerealFormat CerealLimits String (Result CerealValue Error))` | `Alloc,Mut` |  | Parse `source` in `format` into a `CerealValue` tree under the given limits. Past a limit, or on malformed input, it answers `Err`. |
| `cerealDecode` | value | `(-> CerealFormat String (Result CerealValue Error))` | `Alloc,Mut` |  | Parse `source` in `format` into a `CerealValue` tree under the default limits. |
| `cerealSerialize` | value | `(-> CerealFormat (Codec a) a (Result String Error))` | `Alloc,Mut (incomplete)` |  | Encode `value` with the codec and write it in `format`: the one call for turning a typed value into text. |
| `cerealDeserialize` | value | `(-> CerealFormat (Codec a) String (Result a Error))` | `Alloc,Mut (incomplete)` |  | Parse `source` in `format` and decode it with the codec: the one call for turning text into a typed value. |
| `cerealSerializeWith` | value | `(-> CerealFormat CerealLimits (Codec a) a (Result String Error))` | `Alloc,Mut (incomplete)` |  | `cerealSerialize` under the given limits. |
| `cerealDeserializeWith` | value | `(-> CerealFormat CerealLimits (Codec a) String (Result a Error))` | `Alloc,Mut (incomplete)` |  | `cerealDeserialize` under the given limits. |

## `Link`

`stdlib/Link.ax` — 5 public names

Link - a typed index into a vector, stored in the bytes you choose.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `linkTo` | value | `(-> (Vec t) Int (Link t w))` |  |  | A link to the element at `i`. An index outside `0 .. (vecLen v) - 1` stops the program with status 77, as `vecGet` does. |
| `linkNone` | value | `(Link t w)` |  |  | The link to nothing: what `linkIsSome` answers `false` for, and what a zeroed field holds. |
| `linkIsSome` | value | `(-> (Link t w) Bool)` |  |  | Whether the link names an element. |
| `linkIndex` | value | `(-> (Link t w) Int)` |  |  | The index the link names. `linkNone` names none and stops the program with status 77. |
| `linkGet` | value | `(-> (Vec t) (Link t w) t)` |  |  | The element the link names in `v`. `linkNone`, or an index `v` no longer holds, stops the program with status 77. |

## `Map`

`stdlib/Map.ax` — 22 public names

Map - an open-addressing hash map from `Int` keys to values of one
type: a `(Map String)` maps keys to strings, a `(Map Int)` to numbers.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `mapHashPrime` | value | `Int` |  |  | 2^31 - 1, a Mersenne prime: the modulus `Intern`'s polynomial string hash reduces by. |
| `mapHash` | value | `(-> Int Int)` |  |  | Hash `key` to a value in [0, 2^63). |
| `mapSlotOf` | value | `(-> Int Int Int)` |  |  | The slot `key` probes first, in [0, cap). |
| `mapNew` | value | `(Map v)` | `Alloc,Mut` |  | An empty `Map` with `mapDefaultCap` slots. |
| `mapWithCapacity` | value | `(-> Int (Map v))` | `Alloc,Mut` |  | An empty `Map` sized so that `want` entries fit without rehashing. |
| `mapRoundUpPow2` | value | `(-> Int Int)` |  |  | `n` rounded up to a power of two, at least `mapDefaultCap`. |
| `mapLen` | value | `(-> (Map v) Int)` |  |  | How many keys the map holds. |
| `mapCap` | value | `(-> (Map v) Int)` |  |  | How many slots the map has before it grows. |
| `mapUsed` | value | `(-> (Map v) Int)` |  |  | How many slots are live or hold a removed entry's marker: the number that decides when the map rehashes. |
| `mapOwnsVals` | value | `(-> (Map v) Bool)` |  |  | Whether the map holds a share of every value, which it does when its values are a counted type. |
| `mapKeyAt` | value | `(-> (Map v) Int Int)` |  |  | The key in slot `i`, for a slot `mapLiveFrom` answered. A slot outside `0 .. (mapCap m) - 1` stops the program with status 77, as `vecGet`'s does. |
| `mapValAt` | value | `(-> (Map v) Int v)` | `Unsafe` |  | The value in slot `i`, for a slot `mapLiveFrom` answered. A slot outside `0 .. (mapCap m) - 1` stops the program with status 77. |
| `mapNextSlot` | value | `(-> Int Int Int)` |  |  | The next slot after `i`. |
| `mapHas` | value | `(-> (Map v) Int Bool)` |  |  | Whether `key` is in the map. |
| `mapGet` | value | `(-> (Map v) Int v v)` |  |  | The value for `key`, or `dflt` if `key` is absent. |
| `mapInsert` | value | `(-> (Map v) Int v Int)` | `Alloc,Mut` |  | Insert or overwrite, growing first if the load factor demands it. |
| `mapRemove` | value | `(-> (Map v) Int Int)` | `Mut` |  | Remove `key` and its value, if present. Answers 0. |
| `mapLiveFrom` | value | `(-> (Map v) Int (Option Int))` | `Alloc` |  | The first live slot at or after `i`, or `None` when the table has no live slot from there on. `(mapLiveFrom m 0)` starts an iteration; `(mapLiveFrom m (+ prev 1))` continues one. |
| `mapKeys` | value | `(-> (Map v) (Vec Int))` | `Alloc,Mut` |  | Every key, in slot order: the `j`th key and the `j`th element of `mapValues` came out of the same slot, so the two vectors zip. |
| `mapValues` | value | `(-> (Map v) (Vec v))` | `Alloc,Mut` |  | Every live value, in the same slot order `mapKeys` uses, so the two vectors zip element for element. |
| `mapSumVals` | value | `(-> (Map Int) Int)` |  |  | The sum of every live value. |
| `mapSumKeys` | value | `(-> (Map v) Int)` |  |  | The sum of every key. |

## `Mem`

`stdlib/Mem.ax` — 6 public names

Mem - the allocator's counts, and the typed `Addr` for comparing
values by identity.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `MemoryStats` | struct |  |  |  | Allocator counts for the calling binding's arena, in bytes. `heldBytes` includes live values, reusable blocks, cycles and chunk overhead. `filedBytes` is reusable storage; `backlogBytes` is held less filed, not a live-object or leak count. `mappedBytes` includes active and cached chunks. Threads have separate arenas. |
| `memStats` | value | `MemoryStats` | `Alloc` |  | The allocator's counts for the calling binding's arena. The counters are read before the record is allocated, so the snapshot leaves its own record out. |
| `Addr` | struct |  |  |  | Where a value lives, as one sealed word. Make one with `addrOf`; compare with `addrEq`; hash with `addrHash`. An `Addr` takes no share and keeps nothing alive, and nothing turns it back into the value. Compare two only while both values are live, because a freed block's address is handed out again. An immediate value - an `Int`, a `Char`, a nullary constructor - is its own word, so its `Addr` is that word. |
| `addrOf` | value | `(-> a Addr)` |  |  | The address of `x`. The same value always answers the same `Addr`; two values answer equal ones only if they are one value, or are equal immediates. |
| `addrEq` | value | `(-> Addr Addr Bool)` |  |  | Whether `a` and `b` are the address of one value. |
| `addrHash` | value | `(-> Addr Int)` |  |  | A hash of the address, for a table keyed by identity. Equal addresses hash equally, and the result is in [0, 2^63). Block addresses share their low bits, so the word goes through murmur3's 64-bit finaliser first, as `Map.mapHash` does to a key. |

## `Net`

`stdlib/Net.ax` — 79 public names

Net - TCP connections and IP addresses.

    (match (tcpListen "127.0.0.1:7000")
      ((Err e) (eprintln (errorText e)))
      ((Ok lsn)
        (while true
          (match (tcpAccept lsn)
            ((Err e) (eprintln (errorText e)))
            ((Ok conn) (serve conn))))))

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `IpAddr` | struct |  |  |  | An IPv4 or IPv6 address, without a port. One type holds both families, as `SocketAddr` does; `ipIsV4` and `ipIsV6` say which. Make one with `ipV4`, `ipV6` or `ipParse`. |
| `ipV4` | value | `(-> Byte Byte Byte Byte IpAddr)` | `Alloc` |  | The IPv4 address `a.b.c.d`. Each octet is a `Byte`, so one outside 0..255 stops the program with status 80; read text from outside the program with `ipParse`, which answers `Err` instead. |
| `ipV6` | value | `(-> Segment Segment Segment Segment Segment Segment Segment Segment IpAddr)` | `Alloc` |  | The IPv6 address with groups `g0` to `g7` in reading order: `::1` is `(ipV6 0 0 0 0 0 0 0 1)`. |
| `ipParse` | value | `(-> String (Result IpAddr Error))` | `Alloc,Mut` |  | Read an IP address from text: dotted-quad IPv4 such as `10.0.0.1`, or IPv6 in any RFC 4291 section 2.2 form such as `fe80::1`, with no brackets and no port. A zone (`%en0`) is refused, because it names an interface and there is no lookup to resolve it. |
| `ipText` | value | `(-> IpAddr String)` | `Alloc,Mut` |  | The address as text: dotted-quad IPv4, or IPv6 in the RFC 5952 form (lower case, the longest run of zero groups as `::`, an IPv4-mapped address as `::ffff:a.b.c.d`). |
| `ipIsV4` | value | `(-> IpAddr Bool)` |  |  | Whether the address is IPv4. |
| `ipIsV6` | value | `(-> IpAddr Bool)` |  |  | Whether the address is IPv6. |
| `ipOctets` | value | `(-> IpAddr (Vec Int))` | `Alloc,Mut` |  | The address's bytes in network order: four for IPv4, sixteen for IPv6. |
| `ipSegments` | value | `(-> IpAddr (Vec Int))` | `Alloc,Mut` |  | The eight 16-bit groups of an IPv6 address. An IPv4 address answers the groups of its IPv4-mapped form, `::ffff:a.b.c.d`. |
| `ipIsUnspecified` | value | `(-> IpAddr Bool)` |  |  | Whether the address is `0.0.0.0` or `::`, which a listener binds to accept connections on every interface. |
| `ipIsLoopback` | value | `(-> IpAddr Bool)` |  |  | Whether the address is a loopback address: `127.0.0.0/8` or `::1`. |
| `ipIsMulticast` | value | `(-> IpAddr Bool)` |  |  | Whether the address is multicast: `224.0.0.0/4` or `ff00::/8`. |
| `ipIsPrivate` | value | `(-> IpAddr Bool)` |  |  | Whether the address is private: IPv4's RFC 1918 ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), or an IPv6 unique local address (`fc00::/7`, RFC 4193). |
| `ipIsLinkLocal` | value | `(-> IpAddr Bool)` |  |  | Whether the address is link-local: `169.254.0.0/16` or `fe80::/10`. |
| `ipIsBroadcast` | value | `(-> IpAddr Bool)` |  |  | Whether the address is IPv4's broadcast address, `255.255.255.255`. IPv6 has none, so an IPv6 address answers false. |
| `ipIsDocumentation` | value | `(-> IpAddr Bool)` |  |  | Whether the address is reserved for documentation: `192.0.2.0/24`, `198.51.100.0/24` and `203.0.113.0/24` (RFC 5737), or `2001:db8::/32` (RFC 3849). |
| `ipToCanonical` | value | `(-> IpAddr IpAddr)` | `Alloc` |  | The address with an IPv4-mapped IPv6 address turned back into IPv4, and any other address unchanged. A dual-stack listener on `::` sees IPv4 clients as `::ffff:a.b.c.d`; this makes them compare equal to the IPv4 address they are. |
| `ipToV6Mapped` | value | `(-> IpAddr IpAddr)` | `Alloc` |  | An IPv4 address as its IPv4-mapped IPv6 address, `::ffff:a.b.c.d`; an IPv6 address unchanged. |
| `ipEq` | value | `(-> IpAddr IpAddr Bool)` |  |  | Whether two addresses are the same. The families must match too: an IPv4 address is not equal to its IPv4-mapped form until `ipToCanonical` makes it so. |
| `ipCompare` | value | `(-> IpAddr IpAddr Int)` |  |  | -1, 0 or 1 as `a` sorts before, with or after `b`: every IPv4 address before every IPv6 one, and within a family by numeric value. |
| `ipLocalhostV4` | value | `IpAddr` | `Alloc` |  | `127.0.0.1`. |
| `ipLocalhostV6` | value | `IpAddr` | `Alloc` |  | `::1`. |
| `ipUnspecifiedV4` | value | `IpAddr` | `Alloc` |  | `0.0.0.0`: bind a listener here to accept on every IPv4 interface. |
| `ipUnspecifiedV6` | value | `IpAddr` | `Alloc` |  | `::`: bind a listener here to accept on every IPv6 interface. |
| `ipBroadcast` | value | `IpAddr` | `Alloc` |  | `255.255.255.255`. |
| `SocketAddr` | struct |  |  |  | An IP address and a port: what a listener binds and a stream connects to. Make one with `socketAddrNew` or `socketAddrParse`. It holds the kernel's own `sockaddr` bytes, `netAddrMaxBytes` long, built by `Sys.netAddr4` and `Sys.netAddr6`. Sealed, so every SocketAddr is one this module built or the kernel answered. |
| `socketAddrNew` | value | `(-> IpAddr Port SocketAddr)` | `Alloc,Mut` |  | The socket address of `ip` and `port`. |
| `socketAddrParse` | value | `(-> String (Result SocketAddr Error))` | `Alloc,Mut` |  | Read a socket address from text: `a.b.c.d:port` for IPv4, or `[ipv6]:port` with the brackets RFC 3986 section 3.2.2 requires, so the port can't be mistaken for a group. Only numeric addresses: there is no resolver. |
| `socketAddrText` | value | `(-> SocketAddr String)` | `Alloc,Mut` |  | The address as text, `a.b.c.d:port` or `[ipv6]:port`, with the IP written as `ipText` writes it. |
| `socketAddrIp` | value | `(-> SocketAddr IpAddr)` | `Alloc,Mut` |  | The IP address. |
| `socketAddrPort` | value | `(-> SocketAddr Int)` |  |  | The port. |
| `socketAddrWithPort` | value | `(-> SocketAddr Port SocketAddr)` | `Alloc,Mut` |  | The same address with port `port`. |
| `socketAddrWithIp` | value | `(-> SocketAddr IpAddr SocketAddr)` | `Alloc,Mut` |  | The same port with IP address `ip`, which may change the family. |
| `socketAddrIsV4` | value | `(-> SocketAddr Bool)` |  |  | Whether the address is IPv4. |
| `socketAddrIsV6` | value | `(-> SocketAddr Bool)` |  |  | Whether the address is IPv6. |
| `socketAddrEq` | value | `(-> SocketAddr SocketAddr Bool)` | `Alloc,Mut` |  | Whether two socket addresses have the same IP address and port. |
| `socketAddrCompare` | value | `(-> SocketAddr SocketAddr Int)` | `Alloc,Mut` |  | -1, 0 or 1 as `a` sorts before, with or after `b`: by IP address as `ipCompare` orders them, then by port. |
| `TcpListener` | struct |  |  |  | A socket listening for connections. `tcpAccept` answers each one as a `TcpStream`. |
| `TcpStream` | struct |  |  |  | One TCP connection. `pending` holds bytes received but not yet answered: only `tcpReadLine` and `tcpPeek` read ahead, and every reader takes from it first. `nonBlocking` is what `tcpSetNonBlocking` last set, which decides whether EAGAIN means a timeout. |
| `Shutdown` | data |  |  |  | Which half of a connection `tcpShutdown` closes. |
| `pollerAddListener` | value | `(-> Poller TcpListener Int (Result Int Error))` | `Alloc,IO,Mut` |  | Watch the listener under `token` in `p`: a wake answering `token` means a connection is waiting for `tcpAccept`. See `IO.pollerAdd`. |
| `pollerAddStream` | value | `(-> Poller TcpStream Int (Result Int Error))` | `Alloc,IO,Mut` |  | Watch the stream under `token` in `p`: a wake answering `token` means a read will not block. Bytes `tcpBuffered` counts are already here and wake nothing, so read until `WouldBlock` before waiting again. |
| `pollerRemoveListener` | value | `(-> Poller TcpListener (Result Int Error))` | `Alloc,IO,Mut` |  | Stop watching the listener. See `IO.pollerRemove`. |
| `pollerRemoveStream` | value | `(-> Poller TcpStream (Result Int Error))` | `Alloc,IO,Mut` |  | Stop watching the stream. See `IO.pollerRemove`. |
| `tcpListen` | value | `(-> String (Result TcpListener Error))` | `Alloc,IO,Mut` |  | A listener on the address `text` names, such as `0.0.0.0:8080` or `[::1]:0`. Port 0 asks the kernel for a free port, and `tcpListenerLocalAddr` says which. POSIX sets `SO_REUSEADDR` so a restarted server can bind the port its predecessor left in TIME_WAIT. Windows sets `SO_EXCLUSIVEADDRUSE`, preventing another listener from taking the address while this one is live. |
| `tcpListenAddr` | value | `(-> SocketAddr (Result TcpListener Error))` | `Alloc,IO,Mut` |  | A listener on `addr`, as `tcpListen` makes one. |
| `tcpAccept` | value | `(-> TcpListener (Result TcpStream Error))` | `Alloc,IO,Mut` |  | Wait for the next connection and answer it as a blocking stream. `tcpPeerAddr` says who connected. |
| `tcpListenerLocalAddr` | value | `(-> TcpListener (Result SocketAddr Error))` | `Alloc,IO,Mut` |  | The address the listener is bound to, with the kernel's choice of port when it was asked for port 0. |
| `tcpListenerSetNonBlocking` | value | `(-> TcpListener Bool (Result Int Error))` | `Alloc,IO,Mut` |  | Switch the listener between blocking (`false`) and non-blocking (`true`). A non-blocking listener's `tcpAccept` answers `WouldBlock` when nothing is waiting, which a poller wake avoids. |
| `tcpListenerSetTtl` | value | `(-> TcpListener Int (Result Int Error))` | `Alloc,IO,Mut` |  | Set the time-to-live of packets the listener's connections send, the hop limit for IPv6. Accepted streams start with it. |
| `tcpListenerTtl` | value | `(-> TcpListener (Result Int Error))` | `Alloc,IO,Mut` |  | The listener's time-to-live, as `tcpListenerSetTtl` sets it. |
| `tcpListenerTakeError` | value | `(-> TcpListener (Result (Option Error) Error))` | `Alloc,IO,Mut` |  | The listener's pending socket error, cleared by reading it: `(Ok None)` when there is none. |
| `tcpListenerClose` | value | `(-> TcpListener (Result Int Error))` | `Alloc,IO` |  | Close the listener now and report the result. Its last share closes it anyway; after this, any use of it stops the program with status 85. |
| `tcpConnect` | value | `(-> String (Result TcpStream Error))` | `Alloc,IO,Mut` |  | Connect to the address `text` names, such as `127.0.0.1:7000`, and wait until the connection is made or refused. |
| `tcpConnectAddr` | value | `(-> SocketAddr (Result TcpStream Error))` | `Alloc,IO,Mut` |  | Connect to `addr`, as `tcpConnect` does. |
| `tcpConnectTimeout` | value | `(-> SocketAddr Int (Result TcpStream Error))` | `Alloc,IO,Mut` |  | Connect to `addr`, waiting at most `ms` milliseconds: `TimedOut` when the time runs out first. The stream answered is blocking. An `ms` of 0 or less is `InvalidInput`. |
| `tcpBuffered` | value | `(-> TcpStream Int)` |  |  | How many bytes a read-ahead holds: `tcpReadLine` and `tcpPeek` take more than they answer, and the rest waits here for the next read. A poller can't see these bytes. |
| `tcpRead` | value | `(-> TcpStream ReadBuffer Int Int (Result Int Error))` | `Alloc,IO,Mut` |  | Read into `buf[at .. at + count)`: buffered bytes first, then one read of the socket. Answers how many bytes arrived, and 0 when the peer has closed its side. A range outside `buf` stops the program with status 77 before the kernel sees it. |
| `tcpReadSome` | value | `(-> TcpStream Int (Result String Error))` | `Alloc,IO,Mut` |  | Up to `max` bytes as a fresh string: buffered bytes if there are any, otherwise one read of the socket. Empty when the peer has closed its side. A negative `max` stops the program with status 77. |
| `tcpReadExact` | value | `(-> TcpStream Int (Result String Error))` | `Alloc,IO,Mut` |  | Exactly `n` bytes. A peer that closes first answers `UnexpectedEof`, and the bytes that did arrive stay buffered for the next read. It reads no further than `n`, so it leaves nothing behind for a poller to miss. A negative `n` stops the program with status 77. |
| `tcpReadLine` | value | `(-> TcpStream Int (Result (Option String) Error))` | `Alloc,IO,Mut` |  | The next line, without its `\n` or `\r\n`: `(Ok (Some line))`, or `(Ok None)` at end of stream. A last line with no newline is answered as it is. A line longer than `max` bytes answers `InvalidData`. Every failure keeps the bytes that arrived, so after a timeout or `WouldBlock` the next call carries on where this one stopped. |
| `tcpPeek` | value | `(-> TcpStream Int (Result String Error))` | `Alloc,IO,Mut` |  | Up to `max` bytes that the next read will answer, without consuming them: buffered bytes, or one read of the socket when nothing is buffered. Empty at end of stream. |
| `tcpReadAll` | value | `(-> TcpStream (Result String Error))` | `Alloc,IO,Mut` |  | Everything until the peer closes its side, buffered bytes first. |
| `tcpWrite` | value | `(-> TcpStream String (Result Int Error))` | `Alloc,IO,Mut` |  | Write all of `data`, continuing after a short write, and answer `strLen data`. A peer that has closed answers `BrokenPipe` rather than a signal. On a non-blocking stream use `tcpWriteSome`, which says how much went before the stream would block. |
| `tcpWriteSome` | value | `(-> TcpStream String (Result Int Error))` | `Alloc,IO,Mut` |  | One write of as much of `data` as the socket takes now: `(Ok n)`, where `n` can be less than `strLen data`. A non-blocking stream that can take nothing answers `WouldBlock`. Write the rest with `(strSlice data n ...)` when the stream is ready again. |
| `tcpShutdown` | value | `(-> TcpStream Shutdown (Result Int Error))` | `Alloc,IO,Mut` |  | Close one or both halves of the connection and keep the stream: after `ShutdownWrite` the peer reads end of stream, and this side can still read the answer. It acts on the connection itself, so it ends the connection for every process that shares the socket. |
| `tcpClose` | value | `(-> TcpStream (Result Int Error))` | `Alloc,IO` |  | Close the stream now and report the result. Its last share closes it anyway; after this, any use of it stops the program with status 85. |
| `tcpPeerAddr` | value | `(-> TcpStream (Result SocketAddr Error))` | `Alloc,IO,Mut` |  | The peer's address. |
| `tcpLocalAddr` | value | `(-> TcpStream (Result SocketAddr Error))` | `Alloc,IO,Mut` |  | This side's address. |
| `tcpSetNoDelay` | value | `(-> TcpStream Bool (Result Int Error))` | `Alloc,IO,Mut` |  | Turn Nagle's algorithm off (`true`) or back on: with it off, a small write is sent at once rather than held to be joined with the next. |
| `tcpNoDelay` | value | `(-> TcpStream (Result Bool Error))` | `Alloc,IO,Mut` |  | Whether Nagle's algorithm is off, as `tcpSetNoDelay` sets it. |
| `tcpSetReadTimeout` | value | `(-> TcpStream (Option Int) (Result Int Error))` | `Alloc,IO,Mut` |  | How long a read may wait, in milliseconds, before it answers `TimedOut`; `None` waits for ever. `(Some 0)` is `InvalidInput`. |
| `tcpReadTimeout` | value | `(-> TcpStream (Result (Option Int) Error))` | `Alloc,IO,Mut` |  | The read timeout in milliseconds, or `None`. The kernel may round it to its clock's tick. |
| `tcpSetWriteTimeout` | value | `(-> TcpStream (Option Int) (Result Int Error))` | `Alloc,IO,Mut` |  | How long a write may wait, in milliseconds, before it answers `TimedOut`; `None` waits for ever. `(Some 0)` is `InvalidInput`. |
| `tcpWriteTimeout` | value | `(-> TcpStream (Result (Option Int) Error))` | `Alloc,IO,Mut` |  | The write timeout in milliseconds, or `None`. |
| `tcpSetTtl` | value | `(-> TcpStream Int (Result Int Error))` | `Alloc,IO,Mut` |  | Set the time-to-live of packets the stream sends, the hop limit for IPv6. |
| `tcpTtl` | value | `(-> TcpStream (Result Int Error))` | `Alloc,IO,Mut` |  | The stream's time-to-live, as `tcpSetTtl` sets it. |
| `tcpTakeError` | value | `(-> TcpStream (Result (Option Error) Error))` | `Alloc,IO,Mut` |  | The stream's pending socket error, cleared by reading it: `(Ok None)` when there is none. |
| `tcpSetNonBlocking` | value | `(-> TcpStream Bool (Result Int Error))` | `Alloc,IO,Mut` |  | Switch the stream between blocking (`false`) and non-blocking (`true`). A non-blocking read or write that cannot proceed answers `WouldBlock`. |

## `Path`

`stdlib/Path.ax` — 11 public names

Path - taking a filesystem path apart and putting one together.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `pathLastSlash` | value | `(-> String (Option Int))` |  |  | The index of the last `/` in `p`, or `None`. Where `pathBackslashSeparates` is 1, as on Windows, a `\` counts too. |
| `pathDir` | value | `(-> String String)` | `Alloc,Mut` |  | Everything up to and including the last `/`, or "" when `p` names something in the working directory. |
| `pathBase` | value | `(-> String String)` | `Alloc,Mut` |  | Everything after the last `/` - the file name on its own, or `p` entire when there is no separator. |
| `pathWithSlash` | value | `(-> String String)` | `Alloc,Mut` |  | A directory name that ends in `/`, so concatenation forms a path. |
| `pathJoin` | value | `(-> String String String)` | `Alloc,Mut` |  | Join `dir` and `name`, adding a separator when needed. An empty directory or a fully qualified name answers `name`. On Windows a rooted name keeps the directory's drive or share, and a drive-relative name extends the directory only when their drives match. |
| `pathExtIndex` | value | `(-> String (Option Int))` |  |  | The index of the extension's `.` within `p`, or `None`. |
| `pathExt` | value | `(-> String String)` | `Alloc,Mut` |  | The extension INCLUDING its dot (`".ax"`), or "" when there is none. |
| `pathStem` | value | `(-> String String)` | `Alloc,Mut` |  | The base name with its extension removed: `"src/main.ax"` is `"main"`. What a driver names an output after. |
| `pathReplaceExt` | value | `(-> String String String)` | `Alloc,Mut` |  | `p` with its extension replaced by `ext`, which carries its own dot. `(pathReplaceExt "build/main.ax" ".ll")` is `"build/main.ll"`, and a path with no extension simply gains one. |
| `pathIsAbsolute` | value | `(-> String Bool)` |  |  | True when `p` starts at a root. Windows also recognises a drive root such as `C:\work`, a UNC share, and a leading `\` on the current drive. `C:work` remains relative to that drive's working directory. |
| `pathClean` | value | `(-> String String)` | `Alloc,Mut` |  | `p`, lexically simplified to the shortest path naming the same location: doubled `/`s collapse, a `.` segment is dropped, and a real segment is cancelled by the `..` that immediately follows it. It never touches the filesystem, so a symlink is treated as an ordinary name. The rules are Go's `path.Clean` and Python's `posixpath.normpath`. Windows also recognises backslashes as separators and preserves drive-relative prefixes and share roots. |

## `Pre`

`stdlib/Pre.ax` — 2 public names

The standard prelude: the derivers every program can use.

Import with `(import Pre (deriveEq deriveArity))`.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `deriveEq` | macro |  |  |  | Derive structural equality for a `data` type with nullary constructors: `(deriveEq Colour)` declares `eqColour`, of type `(-> Colour Colour Bool)`, with one match arm per constructor. |
| `deriveArity` | macro |  |  |  | Derive a function answering how many fields a value's constructor carries: `(deriveArity Shape)` declares `arityShape`, of type `(-> Shape Int)`. |

## `Rpc`

`stdlib/Rpc.ax` — 7 public names

Rpc.ax — the LSP base protocol's framing, over a file descriptor.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `rdNew` | value | `(-> File Int)` | `Alloc,Mut` |  | A reader over `f`. The record holds a share of `f`, so the file stays open while the reader does. |
| `rdPending` | value | `(-> Int String)` | `Alloc,Mut` |  | A copy of the bytes the reader holds but has not handed out: the start of the next message, which a caller that moves the reader to fresh storage carries across with `rdReseat`. |
| `rdFilled` | value | `(-> Int Int)` |  |  | How many bytes of the reader's buffer hold data. |
| `rdConsumed` | value | `(-> Int Int)` |  |  | How many bytes of the reader's buffer have been handed out. |
| `rdReseat` | value | `(-> Int Int Int Int)` | `Alloc,Mut` |  | Re-seat a reader on freshly allocated storage, carrying `u` bytes of not-yet-consumed input from `addr`. |
| `rpcRead` | value | `(-> Int (Option String))` | `Alloc,IO,Mut` |  | Read one whole message: `Some` its body, or `None` when the stream ended or broke - the caller stops, which is what an LSP does when its client goes away without saying `exit`. |
| `rpcWrite` | value | `(-> File String Int)` | `Alloc,IO,Mut` |  | Frame `body` and write it to `f`. |

## `Str`

`stdlib/Str.ax` — 44 public names

Str - length-prefixed strings, in Axiom.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `strAlloc` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` |  | A `Str` over freshly allocated, zeroed space for `len` bytes. A negative `len` stops the program with status 77, as a bad index does. |
| `strLen` | value | `(-> String Int)` |  |  | The length of `s` in bytes. |
| `strData` | value | `(-> String Int)` |  |  | The address of the first byte of `s`, for the raw-memory calls. It stays valid while `s` is alive. |
| `strOwner` | value | `(-> String Int)` |  |  | The block owning this string's bytes, or 0 for bytes no block owns (a literal's, a syscall buffer's, an arena keep block's interior). |
| `strByte` | value | `(-> String Int Int)` | `Unsafe` |  | The byte at `i`, or 0 when `i` is out of range. |
| `strCStr` | value | `(-> String Int)` | `Alloc,Mut` |  | The bytes of `s` as a NUL-terminated address, for a syscall: free when a NUL follows `s`, and a fresh copy for a short slice. |
| `strIsEmpty` | value | `(-> String Bool)` |  |  | Whether `s` has no bytes. |
| `strCmp` | value | `(-> String String Int)` |  |  | 0 when equal; otherwise negative if `a` sorts before `b`, positive if after - lexicographic by unsigned byte, with a shorter prefix sorting first. |
| `strEq` | value | `(-> String String Bool)` |  |  | Whether `a` and `b` hold the same bytes. |
| `strSlice` | value | `(-> String Int Int String)` | `Alloc,Mut,Unsafe` |  | The `count` bytes of `s` starting at `start`, sharing `s`'s storage. `start` and `count` are clamped to `s`: a range past either end answers the bytes that are there, and a range outside `s` is empty. |
| `strDup` | value | `(-> String String)` | `Alloc,Mut` |  | An owned, NUL-terminated copy of `s`. |
| `concat` | value | `(-> String String String)` | `Alloc,Mut` |  | `a` followed by `b`, as a new string. |
| `strFindByte` | value | `(-> String Int Int (Option Int))` |  |  | Index of the first `byte` at or after `from`, or `None`. |
| `strStartsWith` | value | `(-> String String Bool)` |  |  | Whether `s` begins with `prefix`. |
| `strIsDigit` | value | `(-> Int Bool)` |  |  | Whether the byte is an ASCII digit, `0` to `9`. |
| `strIsAlpha` | value | `(-> Int Bool)` |  |  | Whether the byte is an ASCII letter. |
| `strIsSpace` | value | `(-> Int Bool)` |  |  | Whether the byte is a space, tab, line feed or carriage return. |
| `strHexVal` | value | `(-> Int (Option Int))` |  |  | The value of a hexadecimal digit byte, 0 to 15, or `None` for any other byte. |
| `strIsHexDigit` | value | `(-> Int Bool)` |  |  | Whether the byte is a hexadecimal digit, `0` to `9`, `a` to `f` or `A` to `F`. |
| `strSplit` | value | `(-> String Int (Vec String))` | `Alloc,Mut` |  | Every segment of `s` between occurrences of `byte`, in order. Empty segments are kept, so there is always one more segment than there are separators: `(strSplit "a:" 58)` answers `"a"` and `""`. |
| `strSplitFrom` | value | `(-> String Int Int (Vec String) Int)` | `Alloc,Mut` |  | Split `s` on `byte` starting at index `from`, pushing each piece onto `out`. Answers how many pieces were pushed. |
| `strFromByte` | value | `(-> Byte String)` | `Alloc,Mut,Unsafe` |  | A one-byte `String` holding `b`. |
| `StrBuilder` | struct |  |  |  | A `String` under construction. Appending is amortised constant time per byte, and `strBuilderFinish` answers the bytes as a `String`. Only this module can build one or reach its storage, so no `String` a program holds can change when the builder does. |
| `strBuilderNew` | value | `StrBuilder` | `Alloc,Mut` |  | An empty builder with room for a few bytes before it first grows. |
| `strBuilderWithCapacity` | value | `(-> Int StrBuilder)` | `Alloc,Mut` |  | An empty builder with room for `cap` bytes before it first grows. A `cap` of 0 is allowed, and the first push that adds a byte grows it. A negative `cap` stops the program with status 77, as `strAlloc` does. |
| `strBuilderLen` | value | `(-> StrBuilder Int)` |  |  | How many bytes the builder holds. |
| `strBuilderCap` | value | `(-> StrBuilder Int)` |  |  | How many bytes the builder can hold before it next grows. |
| `strBuilderPush` | value | `(-> StrBuilder String StrBuilder)` | `Alloc,Mut` |  | Append the bytes of `s`. Answers the builder. |
| `strBuilderPushByte` | value | `(-> StrBuilder Byte StrBuilder)` | `Alloc,Mut` |  | Append one byte. Answers the builder. A value outside 0 to 255 stops the program with status 80 at the call, as for `strFromByte`. |
| `strBuilderFinish` | value | `(-> StrBuilder String)` | `Alloc,Mut` | `;@axiom:post((== (strLen result) (strBuilderLen b)))` | The bytes appended so far, as a `String` of exactly that length. The builder stays usable, and later appends don't change the answer. |
| `strJoin` | value | `(-> (Vec String) String String)` | `Alloc,Mut` |  | The strings in `parts` with `sep` between each two, as one new `String`: `(strJoin parts ", ")`. No parts join to "", and one part joins to a copy of itself. |
| `strLower` | value | `(-> String String)` | `Alloc,Mut,Unsafe` | `;@axiom:post((== (strLen result) (strLen s)))` | `s` with every ASCII upper-case letter lowered, or `s` itself when it has none. Bytes above 127 pass through untouched: this is an ASCII fold, not a Unicode case mapping. |
| `strFind` | value | `(-> String String Int (Option Int))` |  |  | The index of the first occurrence of `needle` in `s` at or after `from`, or `None`. An empty needle is found at `from` whenever `from` is inside `s` or at its end, which is the rule that makes `(strFind s "" (strLen s))` answer `(Some (strLen s))` rather than nothing. |
| `strTrim` | value | `(-> String String)` | `Alloc,Mut` |  | `s` without the `strIsSpace` bytes at either end. The result is a slice sharing `s`'s storage, so it is not NUL-terminated unless it ends where `s` does. A string that is all space trims to "". |
| `strParseInt` | value | `(-> String (Option Int))` |  |  | The decimal integer `s` spells - an optional `-`, then one or more ASCII digits and nothing else - or `None`: for an empty string, a sign alone, any other byte, and any value outside the 64-bit range. |
| `format` | macro |  |  |  | `format` — a String, built at compile time from a literal's runs and holes, or the hole lowering applied to anything else. |
| `StrList` | struct |  |  |  | A list of strings packed into one run of bytes. Add with `strListPush`. Read with `strListGet`, or without allocating with `strListByteLen`, `strListByte` and `strListEq`. |
| `strListNew` | value | `StrList` | `Alloc,Mut` |  | An empty list. |
| `strListLen` | value | `(-> StrList Int)` |  |  | How many strings the list holds. |
| `strListPush` | value | `(-> StrList String StrList)` | `Alloc,Mut` |  | Append a copy of the bytes of `s`. Answers the list. |
| `strListByteLen` | value | `(-> StrList Int Int)` |  |  | The length in bytes of string `i`. An `i` out of range stops the program with status 77, as `vecGet` does. |
| `strListByte` | value | `(-> StrList Int Int Int)` |  |  | Byte `j` of string `i`. An `i` or a `j` out of range stops the program with status 77. |
| `strListGet` | value | `(-> StrList Int String)` | `Alloc,Mut` |  | String `i`, sharing the list's bytes the way `strSlice` shares its parent's. Pushing more strings never changes one already read. An `i` out of range stops the program with status 77. |
| `strListEq` | value | `(-> StrList Int String Bool)` |  |  | Whether string `i` holds exactly the bytes of `s`. Allocates nothing. |

## `Sync`

`stdlib/Sync.ax` — 9 public names

A mutual-exclusion lock between `parallel` bindings, in both lowerings
(R-C2, docs/memory-model.md MM-PAR-11).

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Mutex` | struct |  |  |  | A mutex: one owner whose value is the page (MM-PAR-16). |
| `MutexGuard` | struct |  |  |  | What a lock call answers: the lock, held while the guard lives. A resource owner whose cleanup releases the lock (the module header's "the guard"). Only this module makes or opens one, and it is not `shared`. |
| `syncOwnerDead` | value | `Int` |  |  | Above 255, like `sysTimedOut` (1001, the timeout every lock call here answers), so none can be mistaken for a wait status. |
| `syncProbeNanos` | value | `Int` |  |  | How long a waiter sleeps before it looks at the holder: 100 ms. |
| `mutexNew` | value | `(Result Mutex Error)` | `Alloc,IO,Mut` |  | A fresh mutex, free, or `Err` the mapping's error. |
| `mutexLock` | value | `(-> Mutex (Result MutexGuard Error))` | `Alloc,Block,IO,Mut` |  | Wait until this binding holds the lock. `Ok` the guard, which holds the lock until it goes; `Err` code `syncOwnerDead` if the holder is found dead while this waits, or the mutex was poisoned before. |
| `mutexTryLock` | value | `(-> Mutex (Option MutexGuard))` | `Alloc,IO,Mut` |  | Take the lock if it is free right now: `Some` the guard, `None` if it is held - or poisoned, which `mutexOwnerDead` tells apart. |
| `mutexLockTimeout` | value | `(-> Mutex Int (Result MutexGuard Error))` | `Alloc,Block,IO,Mut` |  | `mutexLock`, waiting at most `nanos` nanoseconds. `Ok` the guard; `Err` code `sysTimedOut` when the time ran out with the lock still held by a holder that looks alive; `Err` code `syncOwnerDead` when the holder was found dead. A wait nobody ends is never shorter than `nanos` on a monotonic clock (MM-PAR-12 states Darwin's bound). A non-positive `nanos` is `mutexTryLock` with a reason. |
| `mutexOwnerDead` | value | `(-> Mutex Bool)` |  |  | Whether the mutex is poisoned: a holder was found dead holding it, or a trap ended a guard's scope (the header). |

## `Sys`

`stdlib/Sys.ax` — 52 public names

Sys - portable syscall wrappers.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `sysResult` | value | `(-> String Int (Result Int Error))` | `Alloc` |  | The errno behind a failed result, or 0 if it did not fail. |
| `sysExitWith` | value | `(-> Int Int)` | `IO,Unsafe` |  | End the process with status `code`. Never returns. |
| `sysArgc` | value | `Int` | `IO` |  | How many arguments the process received, including the program name. |
| `sysArg` | value | `(-> Int String)` | `Alloc,IO,Mut` |  | The i-th argument as a Str (0 is the program name), or "" when `i` is out of range. The bytes are the process's own argv storage - NUL-terminated, alive for the whole run, never freed or moved - so wrapping them without copying is sound. |
| `sysEnv` | value | `(-> String String)` | `Alloc,IO,Mut` |  | The value of the environment variable `name`, or "" when it is unset. |
| `sysEnvp` | value | `Int` | `Alloc,IO,Mut` |  | A NULL-terminated copy of the process's own environment vector, in the form a child expects. |
| `sysSpawn` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,IO,Mut,Spawn,Unsafe` |  | Start `path` with argument vector `argv` and environment `envp`. `(Ok pid)`, or `(Err e)` whose code is the errno - and `Err` means no child exists, which is what a caller must not confuse with a child that started and failed. |
| `sysWaitPid` | value | `(-> Int (Result Int Error))` | `Alloc,Block,IO,Mut,Unsafe` |  | Wait for `pid`. `(Ok status)` is the raw wait status; `(Err e)` carries the errno of a wait that could not be performed. |
| `sysExitCode` | value | `(-> Int Int)` |  |  | The exit code carried by a wait status, for a child that exited normally. |
| `sysTermSignal` | value | `(-> Int Int)` |  |  | The signal that killed a child, or 0 if it exited normally. |
| `sysRun` | value | `(-> Int Int Int (Result Int Error))` | `Alloc,Block,IO,Mut,Spawn` |  | Run `path` to completion and answer its exit code. |
| `sysRunPath` | value | `(-> String Int Int (Result Int Error))` | `Alloc,Block,IO,Mut,Spawn` |  | Run `name`, searching `PATH` for it when it contains no slash. |
| `sysRunPathErrTo` | value | `(-> String Int Int String (Result Int Error))` | `Alloc,Block,IO,Mut,Spawn,Unsafe` |  | Run `name` as `sysRunPath` does, with the child's standard error written to the file at `errPath`, created or truncated, rather than to this process's. `(Ok code)` is the child's answer and `(Err e)` a child that never ran, as `sysRunPath` answers; a file that can't be opened is `(Err e)` too, and then nothing runs. |
| `sysSpawnOutErrTo` | value | `(-> Int Int Int String String (Result Int Error))` | `Alloc,IO,Mut,Spawn,Unsafe` |  | Spawn `path` as `sysSpawn` does, with the child's standard output written to the file at `outPath` and its standard error to the file at `errPath`, each created or truncated. Answers the child's pid, as `sysSpawn` does; a file that can't be opened is `(Err e)` and then nothing runs. The swap is the one `sysRunPathErrTo` makes, done for both descriptors and undone as soon as the child exists, because a spawned child keeps the descriptors it was born with. For as long as the spawn itself takes, this process's own output and error are the files too. |
| `sysPid` | value | `Int` | `IO,Unsafe` |  | The calling process's own id, such as a suffix that keeps two processes' scratch files apart. |
| `sysNowMicros` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Microseconds now, from the platform's cheapest correct clock: Darwin answers gettimeofday's timeval (realtime; Darwin's syscall table has no clock_gettime), Linux and FreeBSD answer CLOCK_MONOTONIC via clock_gettime - under the id `clockMonotonicId` names, because the id is not portable: 1 on Linux, and on FreeBSD 4, where 1 is CLOCK_VIRTUAL, the process's CPU time. Windows answers its wall clock through the platform module. A target with no clock call (bare metal) answers `Err` 78, as `sysNowRealtimeNanos` and `sysNowMonotonic` do. |
| `sysHasMonotonic` | value | `Bool` | `Mut` |  | Whether this target has a monotonic clock, so that `sysNowMonotonic`, `sysNowMonotonicNanos` and `sysSleepNanos` answer `Ok`. Linux, FreeBSD, darwin-aarch64 and Windows have one; bare metal and darwin-x86_64 don't. |
| `sysNowMonotonicNanos` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Nanoseconds from a clock that never steps backwards, counted from an unspecified start, or `Err` 78 when this target has none (`sysHasMonotonic`). Linux and FreeBSD read `clock_gettime`'s monotonic clock and darwin-aarch64 the arm64 counter. The 16-byte buffer is the caller's, as above, so a timing loop allocates nothing on the path that answers. |
| `sysNowMonotonic` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Mut` |  | Microseconds from a clock that NEVER steps backwards, or `Err` when this platform has none. The 16-byte buffer is the caller's, as above, so a timing loop allocates nothing on the path that answers. |
| `sysNowRealtimeNanos` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Nanoseconds since 1970-01-01T00:00:00Z from the realtime clock, the wall clock `Chrono.datetimeNowUtc` reads. The system may step it, so two readings do not measure a duration: that is `sysNowMonotonic`'s job. Darwin answers gettimeofday's microseconds times 1000; Linux and FreeBSD answer clock_gettime(CLOCK_REALTIME), and Windows `GetSystemTimePreciseAsFileTime`. A target with no clock call (bare metal) answers `Err` 78, as `sysNowMonotonic` does. An Int of nanoseconds reaches 2262-04-11, and a reading beyond that answers `Err` `errOverflow` rather than wrap. The 16-byte buffer is the caller's, as above. |
| `netAddr4Bytes` | value | `Int` |  |  | The size of an IPv4 socket address block, 16 bytes. |
| `netAddr6Bytes` | value | `Int` |  |  | The size of an IPv6 socket address block, 28 bytes. |
| `netAddrMaxBytes` | value | `Int` |  |  | The size of a buffer that takes either family, which is the larger of the two: a caller does not get to know a peer's family until it has the peer. |
| `netAddr4` | value | `(-> Int Int Int Int Int Int Int)` | `Mut` |  | Write an IPv4 `sockaddr_in` into `buf`, which must hold 16 bytes, and answer `buf`. The four octets are given in reading order, so 127.0.0.1 is `127 0 0 1`. |
| `netAddr6` | value | `(-> Int Int Int Int Int Int Int Int Int Int Int)` | `Mut` |  | Write an IPv6 `sockaddr_in6` into `buf`, which must hold `netAddr6Bytes`, and answer `buf`. |
| `netAddrFamily` | value | `(-> Int Int)` |  |  | The address family in a `sockaddr` - `afInet`, `afInet6`, or whatever else the kernel wrote there. |
| `netAddrPort` | value | `(-> Int Int)` |  |  | The port in a `sockaddr`, decoded from network order. This one does NOT branch on the platform or the family: both layouts diverge in the four bytes before it and agree from byte 2 on, so `sin_port` and `sin6_port` are the same two bytes in the same place. |
| `netAddrSize` | value | `(-> Int Int)` |  |  | How many bytes of `addr` a syscall must be given, read off the family the buffer carries. This is what `IO.socketBind` and `IO.socketConnect` pass, and the reason neither of them takes a length. |
| `netAddrText` | value | `(-> Int String)` | `Alloc,Mut` |  | Render an address as text: a dotted quad for `afInet`, RFC 5952 form for `afInet6`. |
| `netAddrTextPort` | value | `(-> Int String)` | `Alloc,Mut` |  | The same, with the port, in the form a URL authority uses: `127.0.0.1:80` and `[::1]:80`. |
| `netWouldBlock` | value | `(-> Int Bool)` |  |  | Whether a negative answer means "nothing to take yet" rather than a broken socket. This is the whole reason `eAgain` is a capability: the number is 35 on Darwin and 11 on Linux, so an event loop written against a literal runs correctly on the machine it was written on. |
| `sysRandomBytes` | value | `(-> Int Int (Result Int Error))` | `Alloc,Entropy,IO,Unsafe` |  | Fill `n` bytes at `buf` with kernel entropy. `(Ok 0)`, or `(Err e)` whose code is the errno - and on `Err` the buffer's contents are unspecified, so a caller must not read them. |
| `sysSigBit` | value | `(-> Int Int)` |  |  | The `sigset_t` bit for a signal. SIGNAL N IS BIT N-1, an off-by-one that is easy to write the other way and yields the neighbouring signal's mask rather than an error. |
| `sysSignalBlock` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Mut,Unsafe` |  | Block the signals in `mask` so they become observable instead of fatal. `setbuf` is caller scratch of at least 16 bytes: the mask is written as one 64-bit word, and the kernel then copies ITS OWN `sigset_t` width out of the buffer - `sigsetBytes`, which is 4 on Darwin, 8 on Linux and 16 on FreeBSD. Sixteen covers every target, and the bytes between the word and that width are zeroed here rather than left to whatever the caller's buffer held, because on FreeBSD they are signals 65 through 128 and a stale byte there blocks one. Answers `(Result Int Error)`; `Ok 0` on success. Runs once, before a server forks, so that every worker inherits the mask. |
| `sysKill` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Send a signal, which is how a test raises one against itself. |
| `sysForkProcess` | value | `Int` | `IO,Spawn,Unsafe` |  | Start another copy of this process: 0 in the child, the child's pid in the parent, or a negative errno when no child was made. |
| `sysMapShared` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Map `len` bytes, readable and writable (PROT_READ\|PROT_WRITE = 3), shared with every binding spawned after this call; answers the address, page-aligned and zeroed. Unmap it with `sysUnmapShared` once no binding can still touch it - a program obligation, as a handle's single join is (MM-PAR-8). |
| `sysUnmapShared` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Unmap a mapping `sysMapShared` answered. `addr` and `len` must name the whole mapping, and nothing may touch it afterwards. |
| `sysMapPrivate` | value | `(-> Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Map `len` zeroed bytes, readable and writable, private to this process: a fork gets a copy, as it does of the arena. Answers the page-aligned address. |
| `sysUnmapPrivate` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Unmap a mapping `sysMapPrivate` answered. `addr` and `len` must name the whole mapping, and nothing may touch it afterwards. |
| `sysMlock` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Lock `len` bytes at `addr` into memory, so the kernel never writes them to swap. The kernel may refuse: `RLIMIT_MEMLOCK` caps how much an unprivileged process may lock, and on Linux the default cap is a few megabytes. A refusal is an `Err` the caller decides about. |
| `sysMunlock` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Let the `len` bytes at `addr` be paged out again, undoing `sysMlock`. |
| `sysExcludeFromCore` | value | `(-> Int Int (Result Int Error))` | `Alloc,IO,Unsafe` |  | Keep `len` bytes at `addr` out of a core file (`MADV_DONTDUMP` on Linux, `MADV_NOCORE` on FreeBSD). Darwin has no such advice, and answers the unsupported sentinel. `addr` and `len` must name a whole mapping `sysMapPrivate` answered. |
| `sysWaitWord` | value | `(-> Int Int Int)` | `Block,IO` |  | Block while the word at byte address `addr` - 8-aligned, inside a `sysMapShared` mapping - still holds `expected`. It returns when woken, when the word already differs on entry, or spuriously, so the caller re-checks its own condition every time. That is what makes a lost wake impossible: a waker changes the word BEFORE it wakes, so a waiter that read the old value either sees the new one on entry or is already in the queue the wake empties - with one caveat on Linux, which compares only the word's low 32 bits (FUTEX_WAIT, not PRIVATE: the key is the shared page): a waiter preempted across exactly a multiple of 2^32 changes would sleep through them. Darwin compares all 64 (UL_COMPARE_AND_WAIT64_SHARED = 6). Where `waitWordKind` is 0 it returns at once and the caller spins, which is correct and costs a core. No timeout here: `sysWaitWordTimeout` below is the timed form, and it pays for the timespec this one does not need. |
| `sysWakeWord` | value | `(-> Int Int)` | `IO` |  | Wake every binding blocked in `sysWaitWord` on `addr`: FUTEX_WAKE (1) for INT_MAX waiters, or `__ulock_wake` with UL_COMPARE_AND_WAIT64_SHARED \| ULF_WAKE_ALL (6 \| 0x100). Answers 0 for `sysWaitWord`'s reason: a wake with nobody waiting is not an error anyone can act on. |
| `sysTimedOut` | value | `Int` |  |  | The `Error` code a timed operation answers when its time ran out: `chanRecvTimeout`, `chanSendTimeout`, `mutexLockTimeout`, and a task past its deadline. |
| `sysWaitWordTimeout` | value | `(-> Int Int Int Int)` | `Alloc,Block,IO,Mut` |  | Block while the word at `addr` still holds `expected`, for at most `nanos` nanoseconds. `sysWaitWord`'s contract - an 8-aligned word in a `sysMapShared` mapping, and every answer means "re-check your own condition" - plus a bound, and an answer that says why it returned: |
| `sysTimeoutMicros` | value | `(-> Int Int)` | `Alloc,IO,Mut` |  | Microseconds from the clock a timeout is measured on: the monotonic one where the target has it (`sysHasMonotonic`), and the realtime clock where it doesn't (darwin-x86_64). The timed loops above this file add only non-negative steps of this clock, each clamped to the slice the kernel was asked to wait, so a step of a realtime clock moves a wait by at most one slice; MM-PAR-12 states the bound. `buf` is 16 bytes of caller scratch. A clock that cannot be read answers 0, which a caller reads as no time having passed: its wait then ends on the kernel's own timeout rather than early. |
| `sysSleepUntilNanos` | value | `(-> Int (Result Int Error))` | `Alloc,Block,IO,Mut` |  | Sleep until the monotonic clock reads at least `deadline` nanoseconds (`sysNowMonotonicNanos`): `Ok 0` once it does, at once for a deadline already past, or `Err` 78 on a target with no monotonic clock, where nothing could tell when to wake. A wake that comes early, from a signal or the kernel's 71-minute cap on one wait on Darwin, sleeps again for what is left, so the sleep never ends short. A clock that fails mid-sleep answers its `Err`. The thread blocks in the kernel; on FreeBSD, which has no blocking timed wait here, it spins as every timed wait there does. |
| `sysSleepNanos` | value | `(-> Int (Result Int Error))` | `Alloc,Block,IO,Mut` |  | Sleep for at least `nanos` nanoseconds of the monotonic clock: `sysSleepUntilNanos` with a deadline `nanos` from now, saturating at the clock's end. A non-positive `nanos` answers `Ok 0` at once. |
| `sysChildPollBytes` | value | `Int` |  |  | Bytes of caller scratch `sysChildExited` needs: a `siginfo_t` is 104 bytes on Darwin and 128 on Linux. |
| `sysChildExited` | value | `(-> Int Int (Result Bool Error))` | `Alloc,Block,IO,Mut,Unsafe` |  | Has the child `pid` ended? Without reaping it: `Ok True` means it has exited or been killed and is waiting to be reaped - so a join on it will not block - and it is STILL this process's child, still waitable, its pid not free for reuse. `Ok False` means it is running. |

## `Sys.Platform`

`stdlib/Sys/Platform.darwin.ax` — 222 public names

Sys.Platform - the numbers this target's kernel uses: syscall
numbers, open and socket flags, errno values, poll and signal
constants and struct layouts. One file per target; every file
declares the same names, and the build picks the one for the
target being compiled for (this one is `darwin`).

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `sysReadNum` | value | `Int` |  |  | Sys.Platform - Darwin (macOS) syscall numbers and flags. |
| `sysWriteNum` | value | `Int` |  |  | write(fd, buf, count) - BSD 4 |
| `sysOpenNum` | value | `Int` |  |  | open(path, flags, mode) - BSD 5 |
| `sysCloseNum` | value | `Int` |  |  | close(fd) - BSD 6 |
| `sysExitNum` | value | `Int` |  |  | exit(status) - BSD 1 |
| `sysLseekNum` | value | `Int` |  |  | lseek(fd, offset, whence) - BSD 199 |
| `openNeedsDirFd` | value | `Int` |  |  | Darwin has a real `open`, so no `openat` indirection is needed. `Sys.ax` branches on this rather than on an OS name, so adding a platform never means editing portable code. |
| `atFdCwd` | value | `Int` |  |  | Unused on Darwin (see `openNeedsDirFd`), but defined so that `Sys.ax` type-checks against every platform module. |
| `oRdonly` | value | `Int` |  |  | The `O_RDONLY` flag for `open` on this platform: read only. |
| `oWronlyCreateTrunc` | value | `Int` |  |  | O_WRONLY \| O_CREAT \| O_TRUNC = 0x0001 \| 0x0200 \| 0x0400 |
| `oWronlyCreateAppend` | value | `Int` |  |  | O_WRONLY \| O_CREAT \| O_APPEND = 0x0001 \| 0x0200 \| 0x0008 |
| `seekEnd` | value | `Int` |  |  | The `whence` value for `lseek` that measures from the end of the file. |
| `seekSet` | value | `Int` |  |  | The `whence` value for `lseek` that measures from the start of the file. |
| `spawnUsesPosixSpawn` | value | `Int` |  |  | Starting a child process. |
| `sysPosixSpawnNum` | value | `Int` | `Spawn` |  | posix_spawn - BSD 244. |
| `sysWait4Num` | value | `Int` | `Block` |  | wait4(pid, status, options, rusage) - BSD 7. |
| `sysForkNum` | value | `Int` | `Spawn` |  | The syscall number of `fork`, BSD 2, which `sysForkProcess` makes. `sysSpawn` uses `posix_spawn` here instead (`spawnUsesPosixSpawn`). |
| `sysForkArg` | value | `Int` |  |  | The argument the platform's fork syscall takes: 0 where `fork` takes none, the `clone` flags where it is `clone`. |
| `sysExecveNum` | value | `Int` |  |  | The `execve` syscall number, or 0 where the platform runs a child through its own path. |
| `sysUnlinkNum` | value | `Int` |  |  | unlink(path) - BSD 10. |
| `sysMkdirNum` | value | `Int` |  |  | mkdir(path, mode) - BSD 136. Darwin has the plain call, so `openNeedsDirFd` is 0 here and `sysMkdir` uses the two-argument form. |
| `sysRmdirNum` | value | `Int` |  |  | rmdir(path) - BSD 137. |
| `sysRenameNum` | value | `Int` |  |  | rename(from, to) - BSD 128. Darwin has the plain two-argument call, so `openNeedsDirFd` is 0 here and `sysRename` uses it directly. |
| `sysGetdentsNum` | value | `Int` |  |  | Reading a directory. |
| `dirReadNeedsPosition` | value | `Int` |  |  | 1 where reading a directory needs a position argument (`getdirentries`), 0 where `getdents` keeps its own. |
| `direntNameOffset` | value | `Int` |  |  | Where the name starts inside one record. Darwin's 64-bit `dirent` is |
| `cwdUsesFcntlPath` | value | `Int` |  |  | The working directory. |
| `sysCwdNum` | value | `Int` |  |  | fcntl(fd, cmd, arg) - BSD 92. |
| `fGetPath` | value | `Int` |  |  | The `fcntl` command that answers a descriptor's path, or 0 where the platform has none. |
| `eExist` | value | `Int` |  |  | The two errno values portable code above compares against. |
| `eIsDir` | value | `Int` |  |  | The `EISDIR` errno: the path names a directory. |
| `sysGetPidNum` | value | `Int` |  |  | getpid() - BSD 20 |
| `sysClockNum` | value | `Int` |  |  | gettimeofday(tv, tz) - BSD 116. Writes {tv_sec i64, tv_usec i32+pad} to its 16-byte buffer; the register-return interpretation was probed WRONG on arm64 (x0 is 0 on success, never seconds). Verified against the shell clock, 400,000 reads, zero backwards steps, ~200ns/call. |
| `clockIsGettimeofday` | value | `Int` |  |  | 1 where wall-clock time comes from `gettimeofday`, 0 where it comes from `clock_gettime`. |
| `envNamesFoldCase` | value | `Int` |  |  | 1 where environment names match without regard to ASCII case, as Windows matches them, 0 where they match byte for byte. |
| `clockHasMonotonic` | value | `Int` |  |  | Whether this platform can answer a MONOTONIC clock - one that never steps backwards - through a syscall. Darwin cannot: its monotonic clock is the arm64 counter below. |
| `clockMonotonicId` | value | `Int` |  |  | The id `clock_gettime` takes for the monotonic clock: 0, unused here, since `clockIsGettimeofday` sends both clock readers to `gettimeofday`. |
| `clockHasCounter` | value | `Int` |  |  | Whether `Sys.ax` reads the arm64 counter for its monotonic clock: 1. It is `CNTVCT_EL0`, the counter `mach_absolute_time` reads, which never steps backwards and is the same on every core. darwin-x86_64 has no such register; there `sysCounterHz` answers 0, and Darwin has no monotonic clock. |
| `sysSocketNum` | value | `Int` |  |  | socket(domain, type, protocol) - BSD 97. |
| `sysBindNum` | value | `Int` |  |  | bind(fd, addr, addrlen) - BSD 104. THE ADDRLEN IS EXACT: 0, 4, 8, 12, 20, 24 and 28 were each probed and every one answered -22 EINVAL; only 16 - the size of `sockaddr_in` - returned 0. |
| `sysListenNum` | value | `Int` |  |  | listen(fd, backlog) - BSD 106. |
| `sysAcceptNum` | value | `Int` |  |  | accept(fd, addr, addrlen) - BSD 30. |
| `sysConnectNum` | value | `Int` |  |  | connect(fd, addr, addrlen) - BSD 98. On a non-blocking socket this answers -36 EINPROGRESS rather than failing; probed. |
| `sysSetSockOptNum` | value | `Int` |  |  | setsockopt(fd, level, name, val, len) - BSD 105. |
| `sysGetSockOptNum` | value | `Int` |  |  | getsockopt(fd, level, name, val, lenptr) - BSD 118. |
| `sysShutdownNum` | value | `Int` |  |  | shutdown(fd, how) - BSD 134. |
| `sysFcntlNum` | value | `Int` |  |  | fcntl(fd, cmd, arg) - BSD 92, and the number `sysCwdNum` above also holds. They are NOT merged: `sysCwdNum` names "the call that answers the working directory", which is `fcntl(F_GETPATH)` here and `getcwd` on Linux, and a socket has no business reading that name. |
| `afInet` | value | `Int` |  |  | The address family and socket type. `AF_INET` is 2 on both systems - and that agreement is a trap, because `AF_INET6` is 30 here against Linux's 10, so nothing else in this group may be assumed to match. |
| `afInet6` | value | `Int` |  |  | AF_INET6, AND THIS IS THE DIVERGENCE THE PARAGRAPH ABOVE WARNED ABOUT: 30 here against Linux's 10. |
| `sockStream` | value | `Int` |  |  | The `SOCK_STREAM` socket type: a TCP byte stream. |
| `solSocket` | value | `Int` |  |  | THE SOCKET-OPTION NUMBERS ARE WHERE DARWIN AND LINUX PART COMPANY, and they part completely. `SOL_SOCKET` is 0xffff here and 1 on Linux; Darwin's `SO_*` are BSD bitmask-style constants where Linux's are small sequential integers. Not one of the four below shares a value with its Linux twin, so reusing a Linux number here does not fail - it sets some other option. |
| `soReuseAddr` | value | `Int` |  |  | The `SO_REUSEADDR` socket option. |
| `soReusePort` | value | `Int` |  |  | The `SO_REUSEPORT` socket option. |
| `soError` | value | `Int` |  |  | The `SO_ERROR` socket option, read after a non-blocking connect finishes. |
| `fGetFl` | value | `Int` |  |  | fcntl's file-status commands, and the flag a non-blocking socket sets. `O_NONBLOCK` is 4 here and 2048 on Linux. |
| `fSetFl` | value | `Int` |  |  | The `fcntl` command that sets a descriptor's status flags. |
| `fDupFdCloexec` | value | `Int` |  |  | fcntl's F_DUPFD_CLOEXEC: a duplicate of a descriptor, closed on exec. `IO.termRaw` keeps one, so its guard can restore the terminal however the caller's file is closed. |
| `oNonblock` | value | `Int` |  |  | The `O_NONBLOCK` status flag. |
| `eAgain` | value | `Int` |  |  | EAGAIN, which a non-blocking `accept` or `read` answers negated when there is nothing to take yet. 35 here, 11 on Linux - so a caller that compares against a literal is correct on one target and silently wrong on the other, which is the reason this is a name. |
| `eNoSys` | value | `Int` |  |  | ENOSYS - the kernel has no such call: 38 on Linux, 78 on Darwin and FreeBSD. |
| `eOpNotSupp` | value | `Int` |  |  | EOPNOTSUPP - the operation does not apply to this socket or file: 95 on Linux, 102 on Darwin, 45 on FreeBSD. |
| `eNotConn` | value | `Int` |  |  | ENOTCONN - the socket is not connected: 107 on Linux, 57 on the BSDs. |
| `eConnRefused` | value | `Int` |  |  | ECONNREFUSED - nothing listens on the port: 111 on Linux, 61 on the BSDs. |
| `eConnReset` | value | `Int` |  |  | ECONNRESET - the peer reset the connection: 104 on Linux, 54 on the BSDs. |
| `eConnAborted` | value | `Int` |  |  | ECONNABORTED - the connection was aborted before it was accepted: 103 on Linux, 53 on the BSDs. |
| `eHostUnreach` | value | `Int` |  |  | EHOSTUNREACH - no route to the host: 113 on Linux, 65 on the BSDs. |
| `eNetUnreach` | value | `Int` |  |  | ENETUNREACH - no route to the network: 101 on Linux, 51 on the BSDs. |
| `eNetDown` | value | `Int` |  |  | ENETDOWN - the network is down: 100 on Linux, 50 on the BSDs. |
| `eAddrInUse` | value | `Int` |  |  | EADDRINUSE - another socket holds the address: 98 on Linux, 48 on the BSDs. |
| `eAddrNotAvail` | value | `Int` |  |  | EADDRNOTAVAIL - the address is not one of this host's: 99 on Linux, 49 on the BSDs. |
| `eInProgress` | value | `Int` |  |  | EINPROGRESS - a non-blocking connect has started and not finished: 115 on Linux, 36 on the BSDs. |
| `sockaddrHasLenByte` | value | `Int` |  |  | WHETHER `sockaddr_in` OPENS WITH A LENGTH BYTE. It does here and does not on Linux, and the two layouts cannot share a builder: |
| `pollUsesKqueue` | value | `Int` |  |  | 1 where readiness comes from `kqueue`, 0 where it comes from `epoll`. |
| `sysPollCreateNum` | value | `Int` |  |  | kqueue() - BSD 362. Takes no arguments. |
| `sysPollWaitNum` | value | `Int` |  |  | kevent(kq, changelist, nchanges, eventlist, nevents, timeout) - BSD 363, and it is BOTH of epoll's calls: `sysPollCtlNum` names the same number because registering is this call with an eventlist of nothing. |
| `sysPollCtlNum` | value | `Int` |  |  | The syscall number that adds and removes descriptors in the poll set (`kevent` or `epoll_ctl`). |
| `pollEventSize` | value | `Int` |  |  | `struct kevent` is 32 bytes on both 64-bit Darwin arches: |
| `pollEventFdOffset` | value | `Int` |  |  | The byte offset of the descriptor inside one readiness event record. |
| `pollReadFilter` | value | `Int` |  |  | EVFILT_READ. THE ONE VALUE THAT GENUINELY DIVERGES: kqueue's filters are NEGATIVE small integers naming a kind of event, where epoll's are a positive bitmask. -1 here, EPOLLIN = 1 there. It is written into a SIGNED 16-BIT field, so `Sys.ax` masks it to two bytes rather than storing a word. |
| `pollWriteFilter` | value | `Int` |  |  | The writability filter: EVFILT_WRITE (-2) for kqueue, EPOLLOUT (4) for epoll. It goes where `pollReadFilter` goes. |
| `pollAddOp` | value | `Int` |  |  | EV_ADD and EV_DELETE, which coincide with EPOLL_CTL_ADD and EPOLL_CTL_DEL at 1 and 2. The agreement is luck rather than design, so both are named on both platforms instead of being assumed. |
| `pollDelOp` | value | `Int` |  |  | The operation code that removes a descriptor from the poll set. |
| `pollSigsetSize` | value | `Int` |  |  | The size of the mask argument epoll_pwait takes and kevent does not. Zero here because nothing reads it; see the Linux files for why it must be exactly 8 there. |
| `sysRandomNum` | value | `Int` | `Entropy` |  | The syscall number that fills a buffer with random bytes. |
| `randomIsGetentropy` | value | `Int` |  |  | 1 where random bytes come from `getentropy`, 0 where they come from `getrandom`. |
| `randomMaxChunk` | value | `Int` |  |  | The most bytes one random-bytes syscall may fill at a time. |
| `signalUsesSignalFd` | value | `Int` |  |  | 1 where signals are read from a `signalfd`, 0 where a `kqueue` filter delivers them. |
| `sysSigProcMaskNum` | value | `Int` |  |  | sigprocmask(how, set, oset) - BSD 48. |
| `sigBlockHow` | value | `Int` |  |  | SIG_BLOCK, which is 1 HERE AND 0 ON LINUX. The values are not shared and the wrong one is `SIG_UNBLOCK` on Darwin - it would unblock the signal it was asked to block, and the process would take the default disposition and die. |
| `sigsetBytes` | value | `Int` |  |  | Darwin's `sigset_t` is a single `__uint32_t` - FOUR bytes, against Linux's kernel `sigset_t` of eight. Nothing reads a size argument here, but the buffer's width is what the kernel copies. |
| `pollSignalFilter` | value | `Int` |  |  | EVFILT_SIGNAL, the filter that marks an event as a signal rather than a readable socket. Unused on Linux, where the distinction is which descriptor woke instead. |
| `sysSignalFdNum` | value | `Int` |  |  | Unused on Darwin (see `signalUsesSignalFd`), but defined so that `Sys.ax` type-checks against every platform module. |
| `sigInfoSize` | value | `Int` |  |  | The size of one `signalfd_siginfo` record, or 0 where none is read. |
| `sysKillNum` | value | `Int` |  |  | kill(pid, sig) - BSD 37. |
| `sigTerm` | value | `Int` |  |  | SIGTERM and SIGINT AGREE on all four targets, which is worth naming rather than assuming because most of their neighbours do not - SIGUSR1 is 30 here and 10 on Linux. |
| `sigChild` | value | `Int` |  |  | The `SIGCHLD` signal number, or zero when child signals are unavailable. |
| `sigInt` | value | `Int` |  |  | The `SIGINT` signal number. |
| `sigBreak` | value | `Int` |  |  | The Windows Ctrl-Break signal number, or 0 where it is unavailable. |
| `forkChildIsZero` | value | `Int` |  |  | Whether `fork` answers 0 in the child, which is the POSIX convention and what Linux does. Darwin answers the child's pid to both, so `sysForkProcess` normalises; see `sysForkNum` above for the measurement. |
| `usesSyscallAbi` | value | `Int` |  |  | 1 where the platform is reached through raw syscalls, 0 where it goes through the C library or a host shim. |
| `platformWriteFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc` |  | The platform's own way to write to a descriptor where raw `write` is not available; `Err` 78 where the raw syscall is used instead. |
| `platformReadFd` | value | `(-> Int Int Int (Result Int Error))` | `Alloc` |  | The platform's own way to read from a descriptor where raw `read` is not available; `Err` 78 where the raw syscall is used instead. |
| `platformExitWith` | value | `(-> Int Int)` |  |  | The platform's own way to end the process where raw `exit` is not available; -78 where the raw syscall is used instead. |
| `platformOpen` | value | `(-> Int Int Int Int)` |  |  | The platform's own way to open a path where raw `open` is not available; -78 where the raw syscall is used instead. |
| `platformClose` | value | `(-> Int Int)` |  |  | The platform's own way to close a descriptor where raw `close` is not available; -78 where the raw syscall is used instead. |
| `platformSeek` | value | `(-> Int Int Int Int)` |  |  | The platform's own way to move a descriptor's offset where raw `lseek` is not available; -78 where the raw syscall is used instead. |
| `platformPread` | value | `(-> Int Int Int Int Int)` |  |  | The platform's own way to read at an offset where raw `pread` is not available; -78 where the raw syscall is used instead. |
| `platformPwrite` | value | `(-> Int Int Int Int Int)` |  |  | The platform's own way to write at an offset where raw `pwrite` is not available; -78 where the raw syscall is used instead. |
| `platformFsync` | value | `(-> Int Int)` |  |  | The platform's own way to flush a descriptor where raw `fsync` is not available; -78 where the raw syscall is used instead. |
| `platformFtruncate` | value | `(-> Int Int Int)` |  |  | The platform's own way to cut a file where raw `ftruncate` is not available; -78 where the raw syscall is used instead. |
| `platformFlock` | value | `(-> Int Int Int)` |  |  | The platform's own way to lock a file where raw `flock` is not available; -78 where the raw syscall is used instead. |
| `platformNullPath` | value | `String` |  |  | The path of the null device: `/dev/null` here. |
| `platformUnlink` | value | `(-> Int Int)` |  |  | The platform's own way to remove a file where raw `unlink` is not available; -78 where the raw syscall is used instead. |
| `platformRename` | value | `(-> Int Int Int)` |  |  | The platform's own way to rename a path where raw `rename` is not available; -78 where the raw syscall is used instead. |
| `platformMkdir` | value | `(-> Int Int Int)` |  |  | The platform's own way to make a directory where raw `mkdir` is not available; -78 where the raw syscall is used instead. |
| `platformRmdir` | value | `(-> Int Int)` |  |  | The platform's own way to remove a directory where raw `rmdir` is not available; -78 where the raw syscall is used instead. |
| `platformReadDir` | value | `(-> Int Int Int Int)` |  |  | The platform's own way to read a directory where raw `getdents` is not available; -78 where the raw syscall is used instead. |
| `platformGetCwd` | value | `(-> Int Int Int)` |  |  | The platform's own way to read the working directory where raw `getcwd` is not available; -78 where the raw syscall is used instead. |
| `platformSpawn` | value | `(-> Int Int Int Int)` |  |  | The platform's own way to start a child where raw `posix_spawn` or `fork` and `execve` are not available; -78 where the raw syscalls are used instead. |
| `platformWait` | value | `(-> Int Int)` |  |  | The platform's own way to wait for a child where raw `wait4` is not available; -78 where the raw syscall is used instead. |
| `platformKill` | value | `(-> Int Int Int)` |  |  | The platform's own way to signal a child where raw `kill` is not available; -78 where the raw syscall is used instead. |
| `platformChildExited` | value | `(-> Int Int)` |  |  | The platform's own way to poll a child where raw `waitid` is not available; -78 where the raw syscall is used instead. |
| `platformPid` | value | `Int` |  |  | The platform's own way to read the process id where raw `getpid` is not available; -78 where the raw syscall is used instead. |
| `platformSetStd` | value | `(-> Int Int Int)` |  |  | The platform's own way to swap a standard descriptor where raw `dup2` is not available; -78 where the raw syscall is used instead. |
| `pathListSep` | value | `Int` |  |  | The byte that separates the entries of `PATH`: `:` here, `;` on Windows. |
| `pathBackslashSeparates` | value | `Int` |  |  | 1 where a backslash separates path components and `C:` starts an absolute path, so `Sys.sysRunPath` reads either as a path rather than a name to search for. 0 here, where only `/` does. |
| `exeSuffixTried` | value | `Int` |  |  | 1 where a program named without an extension is found as `NAME.exe`, as on Windows; 0 here, where a program is found under its own name. |
| `ttyUsesTermios` | value | `Int` |  |  | Whether this platform's terminal control is the POSIX `termios` trio - read the attributes, edit them, write them back - reached through `ioctl`. Windows answers 0: its mechanism is `GetConsoleMode`/`SetConsoleMode` against a HANDLE, which shares no part of this shape. |
| `sysIoctlNum` | value | `Int` |  |  | ioctl(fd, request, arg) - BSD 54, encoded the way every number in this file is: `0x2000000 \| 54` = 33554486. Probe: `SYS_ioctl = 54 (0x36)`, `SYS_ioctl encoded = 33554486`. |
| `tcGetAttrReq` | value | `Int` |  |  | TIOCGETA - read the terminal attributes into a `struct termios`. |
| `tcSetAttrReq` | value | `Int` |  |  | TIOCSETAF - write the attributes back, after draining pending output and DISCARDING pending input. |
| `tcWinSizeReq` | value | `Int` |  |  | TIOCGWINSZ - read `struct winsize`. |
| `termiosBytes` | value | `Int` |  |  | How many bytes the kernel exchanges through the two requests above, and therefore how large a buffer a caller must hand `Sys.ax` to save a terminal's state in. |
| `termiosFlagBytes` | value | `Int` |  |  | The width of one flag word, which is also the STRIDE of the four of them: `c_iflag` at 0, `c_oflag` at 8, `c_cflag` at 16, `c_lflag` at 24. Probe: `c_iflag@0 c_oflag@8 c_cflag@16 c_lflag@24`, each of `size 8`. The four offsets are `n * termiosFlagBytes` on every platform this library targets, so `Sys.ax` carries one multiplication rather than four constants per module. |
| `termiosCcOff` | value | `Int` |  |  | Where the control-character array `c_cc` begins. Probe: `offsetof c_cc = 32 (size 20, NCCS 20)`. |
| `termiosVminIdx` | value | `Int` |  |  | The two `c_cc` slots that mean something once ICANON is off: how many bytes a `read` must collect before it returns, and how long it waits in tenths of a second. Probe: `VMIN = 16`, `VTIME = 17`. |
| `termiosVtimeIdx` | value | `Int` |  |  | The index of `VTIME` in the termios control-character array. |
| `tiosEcho` | value | `Int` |  |  | c_lflag bits. Probe: `ECHO = 0x8 (8)`, `ICANON = 0x100 (256)`, `ISIG = 0x80 (128)`, `IEXTEN = 0x400 (1024)`. |
| `tiosIcanon` | value | `Int` |  |  | The `ICANON` local-mode flag: line editing by the terminal. |
| `tiosIsig` | value | `Int` |  |  | The `ISIG` local-mode flag: the terminal turns Ctrl-C into a signal. |
| `tiosIexten` | value | `Int` |  |  | The `IEXTEN` local-mode flag: extended input processing. |
| `tiosBrkint` | value | `Int` |  |  | c_iflag bits. Probe: `BRKINT = 0x2`, `ICRNL = 0x100`, `ISTRIP = 0x20`, `IXON = 0x200`. |
| `tiosIcrnl` | value | `Int` |  |  | The `ICRNL` input flag: carriage return becomes newline. |
| `tiosIstrip` | value | `Int` |  |  | The `ISTRIP` input flag: strip the eighth bit. |
| `tiosIxon` | value | `Int` |  |  | The `IXON` input flag: Ctrl-S and Ctrl-Q flow control. |
| `tiosOpost` | value | `Int` |  |  | The one c_oflag bit raw mode touches. Probe: `OPOST = 0x1`, and it is 0x1 on Linux and FreeBSD too. |
| `sysOpenatNum` | value | `Int` |  |  | openat(dirfd, path, flags, mode) - BSD 463 |
| `sysSymlinkNum` | value | `Int` |  |  | symlink(target, link) - BSD 57 |
| `oNoFollow` | value | `Int` |  |  | O_NOFOLLOW = 0x100 |
| `oDirectory` | value | `Int` |  |  | O_DIRECTORY = 0x100000 |
| `eXdev` | value | `Int` |  |  | EXDEV, 18 on every kernel here: what `sysOpenBeneath` answers for a path that would leave its directory, the errno Linux's `openat2(RESOLVE_BENEATH)` answers for the same thing. |
| `sysMmapNum` | value | `Int` |  |  | mmap - BSD 197 (SDK sys/syscall.h), in the 0x2000000 class |
| `sysMunmapNum` | value | `Int` |  |  | munmap - BSD 73 |
| `mapSharedAnon` | value | `Int` |  |  | MAP_SHARED \| MAP_ANON = 0x1 \| 0x1000: a fork keeps these pages the SAME pages, where the arena's MAP_PRIVATE pages become copies |
| `waitWordKind` | value | `Int` |  |  | How a binding blocks on a shared word: 2, `__ulock_wait`/`__ulock_wake` with UL_COMPARE_AND_WAIT64_SHARED, which keys the wait on the page so a waiter and a waker in two processes over one MAP_SHARED page meet. Darwin has no futex. 1 is Linux `futex`; 0 is none (spin) |
| `sysWaitWordNum` | value | `Int` | `Block` |  | __ulock_wait(op, addr, value, timeout_us) - BSD 515 (SDK sys/syscall.h) |
| `sysWakeWordNum` | value | `Int` |  |  | __ulock_wake(op, addr, wake_value) - BSD 516 |
| `eTimedOut` | value | `Int` |  |  | ETIMEDOUT - 60 here and on FreeBSD, 110 on Linux: what a timed `__ulock_wait` answers, negated, when its time ran out (`sysWaitWordTimeout`; measured -60 after a 200 ms wait). |
| `childPollKind` | value | `Int` |  |  | How a parent looks at a child without reaping it (`sysChildExited`): 1, `waitid` with WNOWAIT, the answer read from `si_signo`. 2 is FreeBSD's `wait6`; 0 none. |
| `sysWaitIdNum` | value | `Int` | `Block` |  | waitid(idtype, id, infop, options) - BSD 173 |
| `waitIdPidType` | value | `Int` |  |  | P_PID - 1 here and on Linux, 0 on FreeBSD |
| `waitPollOptions` | value | `Int` |  |  | WEXITED \| WNOHANG \| WNOWAIT = 0x04 \| 0x01 \| 0x20 (SDK sys/wait.h) |
| `mapPrivateAnon` | value | `Int` |  |  | MAP_PRIVATE \| MAP_ANON = 0x2 \| 0x1000 |
| `sysMlockNum` | value | `Int` |  |  | mlock - BSD 203 (SDK sys/syscall.h) |
| `sysMunlockNum` | value | `Int` |  |  | munlock - BSD 204 |
| `sysMadviseNum` | value | `Int` |  |  | madvise - BSD 75 |
| `madvNoDump` | value | `Int` |  |  | Darwin has no madvise that keeps a range out of a core file, so 0. Core files are off unless `ulimit -c` and `kern.coredump` both allow them, and docs/crypto.md says so. |
| `randomUsesRndr` | value | `Int` |  |  | 0: entropy comes from the kernel call above, never from the CPU |
| `sysGetSockNameNum` | value | `Int` |  |  | getsockname - the address a socket is bound to |
| `sysGetPeerNameNum` | value | `Int` |  |  | getpeername - the address of the connected peer |
| `sysSendToNum` | value | `Int` |  |  | sendto - a write that takes flags, for `msgNoSignal` |
| `soRcvTimeo` | value | `Int` |  |  | SO_RCVTIMEO - how long a read may wait, as a struct timeval |
| `soSndTimeo` | value | `Int` |  |  | SO_SNDTIMEO - how long a write may wait |
| `soNoSigPipe` | value | `Int` |  |  | SO_NOSIGPIPE - a write to a closed peer answers EPIPE instead of raising SIGPIPE; 0 where the option does not exist |
| `msgNoSignal` | value | `Int` |  |  | MSG_NOSIGNAL - the same, per write, for `sendto`; 0 where the flag does not exist |
| `ipprotoTcp` | value | `Int` |  |  | IPPROTO_TCP - the level TCP options are set at |
| `tcpNoDelayOpt` | value | `Int` |  |  | TCP_NODELAY - send small writes at once rather than join them |
| `ipprotoIp` | value | `Int` |  |  | IPPROTO_IP - the level of the IPv4 socket options, 0 everywhere. |
| `ipTtl` | value | `Int` |  |  | IP_TTL - the time-to-live of outgoing IPv4 packets: 2 on Linux, 4 on the BSDs. |
| `ipprotoIpv6` | value | `Int` |  |  | IPPROTO_IPV6 - the level of the IPv6 socket options, 41 everywhere. |
| `ipv6UnicastHops` | value | `Int` |  |  | IPV6_UNICAST_HOPS - the hop limit of outgoing IPv6 packets, IPv6's time-to-live: 16 on Linux, 4 on the BSDs. |
| `sysPreadNum` | value | `Int` |  |  | pread(fd, buf, count, offset) - BSD 153 |
| `sysPwriteNum` | value | `Int` |  |  | pwrite(fd, buf, count, offset) - BSD 154 |
| `sysFsyncNum` | value | `Int` |  |  | fsync(fd) - BSD 95. Darwin's fsync leaves the data in the drive's own cache, so Axqlite's pager asks `fcntl(F_FULLFSYNC)` instead and uses this only if the file system refuses that. |
| `sysFtruncateNum` | value | `Int` |  |  | ftruncate(fd, length) - BSD 201 |
| `sysFlockNum` | value | `Int` |  |  | flock(fd, operation) - BSD 131 |
| `fsyncUsesFullFsync` | value | `Int` |  |  | 1: a durable sync is `fcntl(fd, F_FULLFSYNC)`, through `sysFcntlNum` |
| `fFullFsync` | value | `Int` |  |  | F_FULLFSYNC = 51 |
| `oRdwr` | value | `Int` |  |  | O_RDWR = 0x0002 |
| `oCreat` | value | `Int` |  |  | O_CREAT = 0x0200 |
| `oCloexec` | value | `Int` |  |  | O_CLOEXEC = 0x01000000, so a spawned child never inherits the descriptor, or the lock held on it |
| `platformHasClock` | value | `Int` |  |  | Whether `Sys.ax` reads this platform's clocks through `platformMonotonicNanos` and `platformRealtimeNanos`: 0 here, where `clock_gettime` or the counter serves. |
| `platformMonotonicNanos` | value | `(Result Int Error)` | `Alloc` |  | The platform's own monotonic clock in nanoseconds, where raw `clock_gettime` is not available; `Err` 78 where the syscall serves. |
| `platformRealtimeNanos` | value | `(Result Int Error)` | `Alloc` |  | The platform's own wall clock in nanoseconds since the Unix epoch, where raw `clock_gettime` is not available; `Err` 78 where the syscall serves. |
| `platformSleepNanos` | value | `(-> Int (Result Int Error))` | `Alloc` |  | The platform's own sleep for at least `nanos` nanoseconds, where the raw wait is not available; `Err` 78 where the syscall serves. |
| `platformHasEntropy` | value | `Int` |  |  | Whether `Sys.ax` draws entropy through `platformRandomBytes`: 0 here, where the kernel's entropy call serves. |
| `platformRandomBytes` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | The platform's own entropy source, filling `n` bytes at `buf`, where the raw entropy call is not available; `Err` 78 where it serves. |
| `platformWaitWord` | value | `(-> Int Int Int Int)` |  |  | Block until the word at `addr` differs from `expected`, for at most `nanos` nanoseconds (negative: no limit): 0 woken or spurious, 1 timed out, 2 the word already differed. Unreached here: `waitWordKind` picks the kernel's own wait. |
| `platformWakeWord` | value | `(-> Int Int)` |  |  | Wake every waiter on the word at `addr`. Unreached here. |
| `platformMapPrivate` | value | `(-> Int (Result Int Error))` | `Alloc` |  | The platform's own private mapping of `len` zeroed bytes, where raw `mmap` is not available; `Err` 78 where the syscall serves. |
| `platformUnmapPrivate` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | The platform's own release of a private mapping; `Err` 78 here. |
| `platformMapShared` | value | `(-> Int (Result Int Error))` | `Alloc` |  | The platform's own shared mapping of `len` zeroed bytes; `Err` 78 here. |
| `platformUnmapShared` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | The platform's own release of a shared mapping; `Err` 78 here. |
| `platformMlock` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | The platform's own way to pin `len` bytes at `addr` in memory, where raw `mlock` is not available; `Err` 78 where the syscall serves. |
| `platformMunlock` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | The platform's own way to unpin them; `Err` 78 here. |
| `platformSignalBlock` | value | `(-> Int Int (Result Int Error))` | `Alloc` |  | The platform's own signal mask, where raw `sigprocmask` is not available; `Err` 78 where the syscall serves. |
| `platformSocket` | value | `(-> Int Int Int Int)` |  |  | socket(family, type, protocol): the descriptor, or `-errno`. -78 here. |
| `platformBind` | value | `(-> Int Int Int Int)` |  |  | bind(s, addr, len): 0, or `-errno`. -78 here. |
| `platformListen` | value | `(-> Int Int Int)` |  |  | listen(s, backlog): 0, or `-errno`. -78 here. |
| `platformAccept` | value | `(-> Int Int)` |  |  | accept(s): the new descriptor, or `-errno`. -78 here. |
| `platformConnect` | value | `(-> Int Int Int Int)` |  |  | connect(s, addr, len): 0, `-EINPROGRESS` for a non-blocking socket still connecting, or `-errno`. -78 here. |
| `platformSend` | value | `(-> Int Int Int Int)` |  |  | send(s, buf, n): bytes sent, or `-errno`. -78 here. |
| `platformShutdown` | value | `(-> Int Int Int)` |  |  | shutdown(s, how): 0, or `-errno`. -78 here. |
| `platformSetSockOpt` | value | `(-> Int Int Int Int Int Int)` |  |  | setsockopt(s, level, name, val, len): 0, or `-errno`. -78 here. |
| `platformGetSockOpt` | value | `(-> Int Int Int Int Int Int)` |  |  | getsockopt(s, level, name, val, lenCell): 0, or `-errno`. -78 here. |
| `platformSetNonBlocking` | value | `(-> Int Bool Int)` |  |  | Make `s` non-blocking (`on`) or blocking: 0, or `-errno`. -78 here. |
| `platformSocketAddr` | value | `(-> Int Bool Int Int Int)` |  |  | getsockname or (`peer`) getpeername into `addr`, whose length cell is `lenCell`: 0, or `-errno`. -78 here. |
| `platformPoll` | value | `(-> Int Int Int Int)` |  |  | poll over `n` records at `fds`, each a descriptor word, an interest word and a readiness word, for `ms` milliseconds (negative: no limit): the count of ready records, or `-errno`. -78 here. |
| `platformIsConsole` | value | `(-> Int Int)` |  |  | Whether `fd` is a console: 1 or 0. Unreached here. |
| `platformConsoleMode` | value | `(-> Int Int)` |  |  | The console's mode word, or `-errno`. -78 here. |
| `platformConsoleSetMode` | value | `(-> Int Int Int)` |  |  | Set the console's mode word: 0, or `-errno`. -78 here. |
| `platformConsoleSize` | value | `(-> Int Int)` |  |  | The console's window in character cells, as `rows * 65536 + cols`, or `-errno`. -78 here. |

## `Task`

`stdlib/Task.ax` — 30 public names

Structured tasks with typed results across the process boundary
(R-C2, docs/memory-model.md MM-PAR-13).

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `TaskOpts` | struct |  |  |  | `width` children at most (clamped to 1..n); `limit` bytes per answer (0 or more); `deadline` nanoseconds per task from its spawn, 0 for none; `grace` nanoseconds a running task gets after a cancellation; `failFast` cancels the pool at the first error; `token` is `Some` a token from `taskTokenNew`, or `None` for one private to the call; `keep` bytes of answers one call may hold, and `memory` bytes one task's arena may map, each 0 for no bound; `stack` bytes of stack each task runs on, 0 for `taskStackDefault`. |
| `taskOpts` | value | `(-> Int Int TaskOpts)` | `Alloc` |  | No deadline, a 100 ms grace, no fail-fast, a private token, no `keep` or `memory` bound, and the default stack. |
| `taskWithDeadline` | value | `(-> TaskOpts Int TaskOpts)` | `Alloc` |  | The options with a deadline of `nanos` nanoseconds for each task, measured from that task's spawn. |
| `taskWithGrace` | value | `(-> TaskOpts Int TaskOpts)` | `Alloc` |  | The options with `nanos` nanoseconds of grace after cancellation before a task is abandoned. |
| `taskWithFailFast` | value | `(-> TaskOpts Bool TaskOpts)` | `Alloc` |  | The options with fail-fast `on` or off: when on, the first failure cancels the rest. |
| `taskWithToken` | value | `(-> TaskOpts CancelToken TaskOpts)` | `Alloc` |  | The options with `tok` as the cancel token: cancelling it cancels the run. |
| `taskWithKeep` | value | `(-> TaskOpts Int TaskOpts)` | `Alloc` |  | The options with a `keep` budget of `bytes`: the answers one call holds may total at most that many bytes. The answer that would pass it answers `Err taskOverBudgetCode` instead, and the pool is then cancelled as a refused spawn cancels it. `taskFold` holds no answer, so the budget doesn't bound it. 0 is no bound. |
| `taskWithMemory` | value | `(-> TaskOpts Int TaskOpts)` | `Alloc` |  | The options with a `memory` budget of `bytes`: each task's arena may map at most that many bytes beyond what its process began with. A task that asks for more traps 70 in its own process and answers `Err 70`; its siblings and the caller are untouched. 0 is no bound. |
| `taskWithStack` | value | `(-> TaskOpts Int TaskOpts)` | `Alloc` |  | The options with a `stack` budget of `bytes`: each task runs on a stack of that many bytes, rounded up to 64 KiB, mapped in its own process with a guard below it, whichever thread started the pool. A task that recurses past it traps 86 in its own process and answers `Err 86`; its siblings and the caller are untouched. 0 or less is `taskStackDefault`. |
| `taskStackDefault` | value | `Int` |  |  | The stack a task runs on when its options name none: 8 MiB, what Linux and Darwin give a main thread by default. |
| `taskCancelledCode` | value | `Int` |  |  | The error code a cancelled task answers, 1002. |
| `taskTooLargeCode` | value | `Int` |  |  | The error code for a task whose input is larger than the budget allows, 1003. |
| `taskOverBudgetCode` | value | `Int` |  |  | The error code a task answers when its answer would take the call past its `keep` budget, 1012. |
| `taskPollNanos` | value | `Int` |  |  | How often a sleeping pool looks at its running children: 10 ms. |
| `CancelToken` | struct |  |  |  | A cancellation token: one owner whose value is a shared page - word 0 the cancelled flag, word 1 the event counter a pool sleeps on (MM-PAR-16). |
| `taskTokenNew` | value | `(Result CancelToken Error)` | `Alloc,IO` |  | A fresh token, not set, or `Err` the mapping's error. |
| `taskCancel` | value | `(-> CancelToken Int)` | `IO,Mut` |  | Set the token and wake every pool sleeping on it. Idempotent. |
| `taskCancelled` | value | `(-> CancelToken Bool)` |  |  | Whether the token is set: the poll a cooperative task makes. |
| `taskMap` | value | `(-> (-> Int String) Int Int Int (Vec (Result String Error)))` | `Alloc,Block,IO,Mut,Spawn` |  | `f i` for every `i` in `0 .. n`, at most `width` at once, each answer at most `limit` bytes: one `Result` per task in submit order. No deadline, no fail-fast, a private token. |
| `taskMapWith` | value | `(-> (-> Int String) Int TaskOpts (Vec (Result String Error)))` | `Alloc,Block,IO,Mut,Spawn` |  | `taskMap` with every option (`TaskOpts`). |
| `taskMapRanges` | value | `(-> (-> Int Int String) Int Int TaskOpts (Vec (Result String Error)))` | `Alloc,Block,IO,Mut,Spawn` |  | Run `worker start end` on contiguous half-open ranges covering `0 .. count`. `grain` is the maximum items per range, clamped to one. Each range runs in a fresh child and answers one `Result` in range order. Captures are isolated between ranges; work inside one range shares that child's state. All options and budgets apply per range. |
| `taskMapDecoded` | value | `(-> (-> Int String) (-> String (Result a Error)) Int Int Int (Vec (Result a Error)))` | `Alloc,Block,IO,Mut,Spawn` |  | Decode each successful answer in the parent, in submit order. Task failures pass through unchanged and never call `decode`. The encoded answers keep `taskMap`'s byte limit; decoded storage is the decoder's responsibility and the result vector holds n values. |
| `taskMapDecodedWith` | value | `(-> (-> Int String) (-> String (Result a Error)) Int TaskOpts (Vec (Result a Error)))` | `Alloc,Block,IO,Mut,Spawn` |  | All task options, with parent-side decoding. Decoder errors belong to their result slots; `failFast` concerns worker failures, not decoding. Delivery calls `decode` before starting more work, so a slow decoder can delay submission and deadline/cancellation handling. |
| `taskFold` | value | `(-> (-> Int String) Int TaskOpts Int (-> Int Int (Result String Error) Int) Int)` | `Alloc,Block,IO,Mut,Spawn (incomplete)` |  | Fold the answers in submit order without keeping them: `step acc i r` for each task, starting from `init`, answering the last `acc`. Each answer and everything the step allocates are reclaimed on return. A retained mark cell is refreshed before delivery, then reset after it. The pool's state and the accumulator were allocated before that mark. `scoped(step)` checks each invocation: supplied references and fresh allocations cannot escape into captured state. Pass a lambda directly, a non-nullary function declaration, or a parameter with the same tag. The accumulator carries scalar bits. taskMapWith retains answers. |
| `taskMapWords` | value | `(-> (-> Int Int) Int Int (Vec Int))` | `Alloc,Block,IO,Mut,Spawn` |  | Run `f i` for every `i` in `0 .. n`, at most `width` at once, answering the results in SUBMIT order. |
| `taskMapWordsChecked` | value | `(-> (-> Int Int) Int Int (Vec (Result Int Error)))` | `Alloc,Block,IO,Mut,Spawn,Unsafe` |  | Run `f i` for every `i` in `0 .. n`, at most `width` at once, answering one `Result` per slot in SUBMIT order: `Ok` the thunk's word, `Err` the wait status of a slot whose thunk trapped. |
| `taskArgvVector` | value | `(-> (Vec String) Int)` | `Alloc,Mut` |  | A null-terminated argv for `execve` or `posix_spawn`. Every string passes through `strCStr`, which copies a slice when it needs a terminator. The array lives in the caller's arena. |
| `taskRunCommand` | value | `(-> (Vec String) (Result Int Error))` | `Alloc,Block,IO,Mut,Spawn` |  | Run one argument vector. Element 0 is the program, looked up on `PATH`. An empty vector answers `Err` 2 without starting a process. |
| `taskRunCommands` | value | `(-> (Vec (Vec String)) Int (Vec Int))` | `Alloc,Block,IO,Mut,Spawn` |  | Run argument vectors at up to `width` at once, in submit order. Each slot contains its exit code, 128 plus its terminating signal, or a negative errno when the program could not start. |
| `taskMapCompute` | value | `(-> (-> Int Int) Int TaskOpts (Vec (Result Int Error)))` | `Alloc,Block,IO,Mut,Spawn` |  | Map an Int-to-Int numeric computation with the ordinary Task budgets. Results are submit-ordered. Each word crosses as exactly eight bytes; the byte limit and keep budget apply to those bytes. Numeric conversion is explicit. `compute(worker)` checks primitive captures and the entire reachable numeric program, including local accumulators and helpers. |

## `Task.Worker`

`stdlib/Task/Worker.ax` — 18 public names

Task.Worker - isolated executable workers with bounded byte messages.

Build a separate executable whose main calls `workerServe handler`.
`workerMap` starts that executable afresh for every input. Strings are
binary messages: no closure or managed reference crosses the process.
Standard output and standard error remain ordinary side effects.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `WorkerStack` | data |  |  |  | NativeStack uses the executable's ordinary stack. StackBytes requests a guarded usable stack budget; unsupported targets refuse it before launch. |
| `WorkerCancelToken` | struct |  |  |  | One process-local token shared by pools and cancellation callers. |
| `WorkerOpts` | struct |  |  |  | Width, per-message byte bounds, time in nanoseconds, cumulative kept result bytes, and additional arena bytes after the child installs input. Zero deadline, keep or memory means no bound. NativeStack is explicit. |
| `workerOpts` | value | `(-> Int Int Int WorkerOpts)` | `Alloc` |  | Defaults: no deadline, 100 ms cancellation grace, no fail-fast or cumulative memory bound, a private token and the executable's native stack. |
| `workerWithDeadline` | value | `(-> WorkerOpts Int WorkerOpts)` | `Alloc` |  | A per-invocation deadline, measured from its spawn. |
| `workerWithGrace` | value | `(-> WorkerOpts Int WorkerOpts)` | `Alloc` |  | Grace after cancellation or deadline before forced termination and join. |
| `workerWithFailFast` | value | `(-> WorkerOpts Bool WorkerOpts)` | `Alloc` |  | Cancel the remaining pool when an invocation fails. |
| `workerWithToken` | value | `(-> WorkerOpts WorkerCancelToken WorkerOpts)` | `Alloc` |  | Share cancellation with another pool or caller in this process. |
| `workerWithKeep` | value | `(-> WorkerOpts Int WorkerOpts)` | `Alloc` |  | Bound the sum of retained successful result bytes; zero is unbounded. |
| `workerWithMemory` | value | `(-> WorkerOpts Int WorkerOpts)` | `Alloc` |  | Bound arena mappings added after the endpoint has copied its input. |
| `workerWithStack` | value | `(-> WorkerOpts WorkerStack WorkerOpts)` | `Alloc` |  | Choose the executable's native stack or a supported guarded byte budget. |
| `workerTokenNew` | value | `(Result WorkerCancelToken Error)` | `Alloc,IO,Unsafe` |  | Allocate a cancellation token; it starts unset and cannot be reset. |
| `workerCancel` | value | `(-> WorkerCancelToken Int)` | `Mut,Unsafe` |  | Cancel every pool using this token. Running children observe it through their own WorkerContext when the parent next scans its running children. |
| `workerTokenCancelled` | value | `(-> WorkerCancelToken Bool)` | `Unsafe` |  | Whether this process-local token has been set. |
| `WorkerContext` | struct |  |  |  | A live endpoint invocation. Retaining it beyond workerServe does not extend the invocation: querying an expired context raises resource trap85. |
| `workerCancelled` | value | `(-> WorkerContext Bool)` |  |  | Poll a cooperative cancellation request without allocating. |
| `workerServe` | value | `(-> (-> WorkerContext String String) Int)` | `Alloc,IO,Mut` |  | The main of a dedicated worker executable calls this once with its handler. The launcher supplies a reserved three-argument transport suffix. Invalid invocation answers64; malformed transport answers22. |
| `workerMap` | value | `(-> (Vec String) (Vec String) WorkerOpts (Vec (Result String Error)))` | `Alloc,Block,IO,Mut,Spawn` |  | Start a fresh executable for every input, with at most width children. Answers preserve input order. Every child is joined before this returns; result publication alone never releases its slot. Cancellation is checked between launches and running-child scans, with a 1 ms sleep between scans. Grace expires before forced termination and join. |

## `Test`

`stdlib/Test.ax` — 8 public names

Test - assertions, and the effect an assertion failure raises.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `Assert` | effect |  |  |  | The effect a failed assertion performs. |
| `assertEq` | value | `(-> String Int Int Int)` | `Alloc,Assert,IO,Mut` |  | Two `Int`s are equal. |
| `assertNe` | value | `(-> String Int Int Int)` | `Alloc,Assert,IO,Mut` |  | Two `Int`s are not equal: for a value that should have changed, when naming what it changed to would pin more than the test means to. |
| `assertStrEq` | value | `(-> String String String Int)` | `Alloc,Assert,IO,Mut` |  | Two `String`s are equal, by bytes. |
| `assertTrue` | value | `(-> String Bool Int)` | `Alloc,Assert,IO,Mut` |  | A `Bool` is true. |
| `assertFalse` | value | `(-> String Bool Int)` | `Alloc,Assert,IO,Mut` |  | A `Bool` is false. |
| `assertFloatNear` | value | `(-> String Float Float Float Int)` | `Alloc,Assert,IO,Mut` |  | Two `Float`s are equal within `epsilon`. A computed float rarely equals an exact literal, so choose an `epsilon` that suits the computation. |
| `testFail` | value | `(-> String Int)` | `Alloc,Assert,IO,Mut` |  | Fail unconditionally: for the branch that must not be reached, and for a case not written yet, as `(testFail "todo: the empty input")`. |

## `Tui.Edit`

`stdlib/Tui/Edit.ax` — 62 public names

Tui.Edit — a line editor: buffer, cursor, kills, and a redraw that
survives wrapping.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `LED_GO` | value | `Int` |  |  | Keep editing. |
| `LED_DONE` | value | `Int` |  |  | Enter: the caller takes `ledSnapshot`. |
| `LED_EOF` | value | `Int` |  |  | Ctrl-D on an empty buffer: end of input, the same answer the piped reader gives at the end of its input. |
| `LED_ABORT` | value | `Int` |  |  | Ctrl-C: abandon this line, but not the session. `Tui/Term.ax`'s header says why, and why it can't leave the terminal raw. |
| `LED_RING_MAX` | value | `Int` |  |  | How many kills the ring remembers. |
| `LineEd` | struct |  |  |  | A line being edited: the code points `left` and `right` of the cursor, the kill `ring`, the prompt width and the terminal width the refresh wraps at. |
| `ledRingNew` | value | `(Vec String)` | `Alloc,Mut` |  | The kill ring, created once per session and outliving every line. |
| `ledNew` | value | `(-> (Vec String) String LineEd)` | `Alloc,Mut` |  | One editor over a session's kill ring, with the caller's word set: the bytes besides letters, digits and `_` that count as word characters. |
| `ledReset` | value | `(-> LineEd String Int Int Int)` | `Mut` |  | Prepare for the next physical line. Keeps both vectors' capacity. |
| `ledLen` | value | `(-> LineEd Int)` |  |  | How many code points the line holds. |
| `ledCursor` | value | `(-> LineEd Int)` |  |  | The cursor, as a code-point index: `(vecLen left)`. |
| `ledCpAt` | value | `(-> LineEd Int Int)` |  |  | Code point `i` of the logical buffer, or 0 out of range. |
| `ledRangeStr` | value | `(-> LineEd Int Int String)` | `Alloc,Mut` |  | `cnt` code points from `s`, as a String. |
| `ledSnapshot` | value | `(-> LineEd String)` | `Alloc,Mut` |  | The whole line as a `String`. |
| `ledInsert` | value | `(-> LineEd Int Int)` | `Alloc,Mut` |  | Insert one code point before the cursor. 1 if it went in. |
| `ledInsertStr` | value | `(-> LineEd String Int)` | `Alloc,Mut` |  | Insert every code point of `s` before the cursor. Answers how many went in. |
| `ledSetStr` | value | `(-> LineEd String Int)` | `Alloc,Mut` |  | Replace the buffer, cursor at the end. What history and completion need: one call to put a whole line in. |
| `ledBackspace` | value | `(-> LineEd Int)` | `Mut` |  | Delete the code point before the cursor. Answers 1 when one was deleted, 0 at the start of the line. |
| `ledDelete` | value | `(-> LineEd Int)` | `Mut` |  | Delete the code point under the cursor. Answers 1 when one was deleted, 0 at the end of the line. |
| `ledLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Move the cursor one code point left. Answers 1 when it moved, 0 at the start of the line. |
| `ledRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Move the cursor one code point right. Answers 1 when it moved, 0 at the end of the line. |
| `ledHome` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Move the cursor to the start of the line. Answers how many code points it moved. |
| `ledEnd` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Move the cursor to the end of the line. Answers how many code points it moved. |
| `ledIsWord` | value | `(-> LineEd Int Bool)` |  |  | Whether code point `cp` is part of a word for the word-wise motions: a letter, a digit, `_` or anything outside ASCII. |
| `ledWordLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Move the cursor to the start of the previous word, by readline's rule: skip a run of non-word characters, then a run of word characters. Answers how many code points it moved. |
| `ledWordRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Move the cursor to the end of the next word. Answers how many code points it moved. |
| `ledWordRightSpan` | value | `(-> LineEd Int)` |  |  | How many code points a forward word kill would take, without moving the cursor. |
| `ledKillPush` | value | `(-> LineEd String Int Int)` | `Alloc,Mut` |  | Put `text` on the kill ring. A kill in the same direction `dir` as the last one extends its entry, so repeated kills yank back as one. Answers 0. |
| `ledRingIdx` | value | `(-> LineEd Int)` |  |  | Which kill-ring entry a yank would take. |
| `ledKillToEnd` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Kill from the cursor to the end of the line onto the ring. Answers how many code points were killed. |
| `ledKillToStart` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Kill from the start of the line to the cursor onto the ring. Answers how many code points were killed. |
| `ledKillWordLeft` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Kill from the start of the previous word to the cursor onto the ring. Answers how many code points were killed. |
| `ledKillWordRight` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Kill from the cursor to the end of the next word onto the ring. Answers how many code points were killed. |
| `ledYank` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Insert the newest kill-ring entry at the cursor. Answers how many code points were inserted, 0 with an empty ring. |
| `ledYankPop` | value | `(-> LineEd Int)` | `Alloc,Mut` |  | Alt-y: replace the text the last yank inserted with the next older kill-ring entry. Pressed anywhere but straight after a yank, it changes nothing. |
| `tuiVisLen` | value | `(-> String Int)` |  |  | The display width of a string: no `ESC [ ... m` sequence counted, and no UTF-8 continuation byte counted. |
| `tuiCat` | value | `(-> (Vec String) String)` | `Alloc,Mut` |  | Every fragment in `v`, concatenated, with each byte copied once. |
| `ledCharCols` | value | `(-> Int Int)` |  |  | The display width of one code point: 1 for every code point. Not yet: wide and zero-width characters count as 1 too. |
| `ledColsBefore` | value | `(-> LineEd Int Int)` |  |  | The columns the first `k` code points occupy. |
| `ledCols` | value | `(-> LineEd Int)` |  |  | The width to compute with: the terminal's, or 80 when it answered something a division can't use. |
| `ledContentCols` | value | `(-> LineEd Int)` |  |  | How many terminal columns the prompt and the whole line take, before wrapping. |
| `ledRowOf` | value | `(-> LineEd Int Int)` |  |  | The screen row, counted from the prompt's row, that code point `k` lands on after wrapping. |
| `ledColOf` | value | `(-> LineEd Int Int)` |  |  | The screen column that code point `k` lands on after wrapping. |
| `ledRowsUsed` | value | `(-> LineEd Int)` |  |  | How many screen rows the prompt and line take after wrapping. |
| `ledCup` | value | `(-> Int Int String)` | `Alloc,Mut` |  | `ESC [ n <final>`, or "" when n < 1 so a zero-distance move costs no bytes. 65 A up, 66 B down, 67 C forward, 68 D back. |
| `ledClearScreen` | value | `(-> Int String)` | `Alloc,Mut` |  | `ESC [ H ESC [ 2 J` - cursor home, erase the whole screen. Ctrl-L. |
| `ledEraseRow` | value | `(-> Int String)` | `Alloc,Mut` |  | `ESC [ 0 K`: erase from the cursor to the end of the row. |
| `ledEraseOld` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut` |  | Erase what the previous refresh drew and leave the cursor at column 0 of the first row. |
| `ledRefreshFull` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut,Unsafe` |  | Append to `out` the sequences that redraw the whole line across as many rows as it wraps to, and put the cursor back. Answers 0. |
| `ledRefreshWindow` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut,Unsafe` |  | Append to `out` the escape sequences that redraw the line within the terminal's width and put the cursor back. Answers 0. |
| `ledRefresh` | value | `(-> LineEd (Vec String) Int)` | `Alloc,Mut` |  | Append to `out` the redraw of the line: the windowed repaint when the line is taller than the terminal, the full one otherwise. |
| `ledRefreshFullPainted` | value | `(-> LineEd (Vec String) String Int)` | `Alloc,Mut,Unsafe` |  | Append to `out` the sequences that redraw the whole line from `painted`, the line already run through a highlighter, and put the cursor back. Answers 0. |
| `ledRefreshPainted` | value | `(-> LineEd (Vec String) String Int)` | `Alloc,Mut` |  | Like `ledRefresh`, but the full repaint draws `painted` - the caller's rendering of the current buffer - instead of the plain snapshot. See `ledRefreshFullPainted` for the width contract that makes the cursor land correctly. |
| `ledResize` | value | `(-> LineEd Int Int Int)` | `Mut` |  | Record the terminal's current size before a refresh. Answers 1 when the size changed. |
| `ledApply` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` |  | Apply one key event to the line, appending any redraw to `out`. Answers `LED_DONE` on Enter, `LED_EOF` on end of input, and 0 otherwise. |
| `ledIsKillKey` | value | `(-> KeyEv Bool)` |  |  | Whether the key is a kill: Ctrl-K, Ctrl-U or Ctrl-W. |
| `ledIsYankKey` | value | `(-> KeyEv Bool)` |  |  | Whether the key is a yank: Ctrl-Y. |
| `ledByWord` | value | `(-> KeyEv Bool)` |  |  | Whether a motion key moves by word: it carries Ctrl or Alt. |
| `ledDispatch` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` |  | Route one key event to the editing operation it names and append any redraw to `out`. Answers `LED_DONE` on Enter, `LED_EOF` on end of input, 0 otherwise. |
| `ledNavKey` | value | `(-> LineEd KeyEv Int)` | `Alloc,Mut` |  | Apply an arrow, Home or End key to the line. Up, Down and Tab do nothing here: history and completion are the caller's. |
| `ledCharKey` | value | `(-> LineEd KeyEv Int)` | `Alloc,Mut` |  | Apply a printable key, or an Alt-<letter> word command: Alt-b and Alt-f move by word, Alt-d kills one and Alt-y yank-pops. |
| `ledCtrlKey` | value | `(-> LineEd KeyEv (Vec String) Int)` | `Alloc,Mut` |  | Apply a control key, with readline's bindings. Ctrl-N and Ctrl-P are left to the caller's history. |

## `Tui.Keys`

`stdlib/Tui/Keys.ax` — 43 public names

Tui.Keys — terminal input bytes to key events, as a pure function.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `KEY_NONE` | value | `Int` |  |  | An event that means nothing to the editor: a mouse report, a device reply, a stray byte. Its `used` is still the bytes to advance by. |
| `KEY_MORE` | value | `Int` |  |  | The bytes so far are a strict prefix of a key: read more, or settle it with `keyResolve`. `keyNext` never answers this kind. |
| `KEY_EOF` | value | `Int` |  |  | The key kind for end of input: Ctrl-D on an empty line, or the input closing. |
| `KEY_CHAR` | value | `Int` |  |  | `cp` is the code point. |
| `KEY_CTRL` | value | `Int` |  |  | A control key, with the letter in `cp`, 64 to 95: Ctrl-A is 65, Ctrl-@ is 64 and Ctrl-_ is 95. |
| `KEY_ENTER` | value | `Int` |  |  | The key kind for Enter. |
| `KEY_TAB` | value | `Int` |  |  | The key kind for Tab. |
| `KEY_BACKSPACE` | value | `Int` |  |  | The key kind for Backspace. |
| `KEY_ESCAPE` | value | `Int` |  |  | The key kind for a lone Escape. |
| `KEY_UP` | value | `Int` |  |  | The key kind for the up arrow. |
| `KEY_DOWN` | value | `Int` |  |  | The key kind for the down arrow. |
| `KEY_RIGHT` | value | `Int` |  |  | The key kind for the right arrow. |
| `KEY_LEFT` | value | `Int` |  |  | The key kind for the left arrow. |
| `KEY_HOME` | value | `Int` |  |  | The key kind for Home. |
| `KEY_END` | value | `Int` |  |  | The key kind for End. |
| `KEY_DELETE` | value | `Int` |  |  | The key kind for Delete. |
| `KEY_INSERT` | value | `Int` |  |  | The key kind for Insert. |
| `KEY_PGUP` | value | `Int` |  |  | The key kind for Page Up. |
| `KEY_PGDN` | value | `Int` |  |  | The key kind for Page Down. |
| `KEY_FN` | value | `Int` |  |  | `cp` is the function-key number: KEY_FN with cp 5 is F5. |
| `MOD_SHIFT` | value | `Int` |  |  | The Shift bit in a key event's `mods`. |
| `MOD_ALT` | value | `Int` |  |  | The Alt bit in a key event's `mods`. |
| `MOD_CTRL` | value | `Int` |  |  | The Ctrl bit in a key event's `mods`. |
| `keyCsiMax` | value | `Int` |  |  | How many bytes of a well-formed CSI this decoder will tolerate before calling it line noise. A wedged terminal spewing digits cannot otherwise grow the pending prefix without bound. |
| `keyStrMax` | value | `Int` |  |  | How many bytes of an OSC or DCS string body this decoder will tolerate before calling it line noise. |
| `KeyEv` | struct |  |  |  | One decoded key: its `kind` (a `KEY_*` constant), the code point `cp` for a character or control key, the `MOD_*` bits in `mods`, and how many input bytes it `used`. |
| `keyScanCtrl` | value | `(-> Int KeyEv)` | `Alloc` |  | The key event for one control byte: Enter for 13 or 10, Backspace, Tab, Escape, Ctrl-D as end of input, and `KEY_CTRL` with the letter for the rest. |
| `keyCsiEnd` | value | `(-> String Int Int Int)` |  |  | The index of the final byte of the CSI sequence that starts at `i0`, or -1 when the sequence is not complete within `len`. |
| `keyCsiParam` | value | `(-> String Int Int Int Int)` |  |  | The `idx`-th numeric parameter of the CSI sequence starting at `i0`, or 0 when it has none. |
| `keyCsiPrivate` | value | `(-> String Int Int Bool)` |  |  | A CSI whose first parameter byte is `<`, `=`, `>` or `?` is a private form: a mouse report, a device-attributes reply, a mode report. None of them is a keystroke. |
| `keyTildeKind` | value | `(-> Int Int)` |  |  | The key a `~`-final CSI names, from its first parameter. |
| `keyTildeFn` | value | `(-> Int Int)` |  |  | F1..F12 out of a `~`-final parameter, or 0 for one that names none. |
| `keyFinalKind` | value | `(-> Int Int)` |  |  | The key a letter-final CSI or SS3 names. |
| `keyFromCsi` | value | `(-> String Int Int Int KeyEv)` | `Alloc` |  | The key event a complete CSI sequence from `off` to its final byte `fin` means: arrows, Home, End, Delete, page keys and their modifier bits. |
| `keyFromSs3` | value | `(-> String Int Int KeyEv)` | `Alloc` |  | The key event an SS3 sequence (`ESC O x`) at `off` means, or `KEY_MORE` when it is not complete within `len`. |
| `keyStrEnd` | value | `(-> String Int Int Int)` |  |  | The index just past the string terminator (`ESC \\` or BEL) of the control string starting at `i0`, or -1 when it is not complete within `len`. |
| `keyScanUtf8` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` |  | The key event for one UTF-8 encoded character at `off`, or `KEY_MORE` when its bytes are not all there yet. |
| `keyScan` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` |  | Decode the key that starts at byte `off` of the `len` bytes in `src`: a character, a control byte or an escape sequence. `KEY_MORE` means the bytes so far do not finish a key. |
| `keyScanEsc` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` |  | Decode the key that starts with the ESC at `off`: a CSI or SS3 sequence, a control string, Alt with a key, or a lone Escape. |
| `keyScanCsi` | value | `(-> String Int Int KeyEv)` | `Alloc` |  | Decode the CSI escape sequence at `off`, or answer `KEY_MORE` when it is not complete. |
| `keyScanStr` | value | `(-> String Int Int KeyEv)` | `Alloc` |  | Skip the control string (OSC, DCS, APC) at `off`, answering `KEY_NONE` with its length, or `KEY_MORE` when it is not complete. |
| `keyScanAlt` | value | `(-> String Int Int KeyEv)` | `Alloc,Mut` |  | ESC <anything else> is Alt-that-key: decode the key at off+1 and OR MOD_ALT into it. `used` grows by the ESC. |
| `keyResolve` | value | `(-> String Int Int KeyEv)` | `Alloc` |  | Decode the key at `off` and settle what `keyScan` leaves open: a lone Escape at the end of the input is Escape, and a sequence still incomplete is `KEY_MORE`. |

## `Tui.Term`

`stdlib/Tui/Term.ax` — 13 public names

Tui.Term — the only part of the TUI that touches a descriptor.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `termBufBytes` | value | `Int` |  |  | The most one `read` takes: enough that a pasted line arrives in one syscall and redraws about once. |
| `keyEscTimeoutMs` | value | `Int` |  |  | How long to wait for the rest of an escape sequence before deciding there is no rest. |
| `mkKeyIn` | value | `(-> File Int KeyIn)` | `Alloc,IO,Mut` |  | A key reader over `in`. With `active` 0 it is inert, with no poller and nothing ever read, for input that isn't a terminal. |
| `keyInPending` | value | `(-> KeyIn Int)` |  |  | Bytes read but not yet consumed. The redraw coalescing asks this. |
| `keyInFill` | value | `(-> KeyIn Int Int)` | `Alloc,IO,Mut` |  | Read more input into the key reader, waiting at most `timeoutMs` milliseconds (-1 waits without limit). Answers how many bytes arrived, 0 on timeout, and -1 when the input closed. |
| `keyNext` | value | `(-> KeyIn KeyEv)` | `Alloc,IO,Mut` |  | The next decoded key from the reader, reading more input when the buffered bytes do not finish one. |
| `termReadSize` | value | `(-> KeyIn Int)` | `Alloc,IO,Mut` |  | Refresh `kin.rows` and `kin.cols` from the terminal on standard output. A failed query records 0 for both. |
| `termWsCols` | value | `(-> KeyIn Int)` |  |  | Columns, or 80. A pty that has never been sized answers 0 with a successful ioctl, so the fallback is on the value and not only on the return code. |
| `termWsRows` | value | `(-> KeyIn Int)` |  |  | The terminal's height in rows from the last window-size query, or 24 when it is unknown. |
| `termRawEnter` | value | `(-> KeyIn Int)` | `Alloc,IO,Mut` |  | Enter raw mode on the reader's file, keeping the guard in `kin.guard`. 0, or the negated errno. Signals are off: see the header. |
| `termRawLeave` | value | `(-> KeyIn Int)` | `Alloc,IO,Mut` |  | Leave raw mode, restoring what `termRawEnter` saved. 0, or the negated errno; 0 when raw mode was never entered. Dropping the reader with raw mode on restores the terminal too, when the guard's last share goes. |
| `termFlush` | value | `(-> (Vec String) Int)` | `Alloc,IO,Mut` |  | Write every piece in `out` to the terminal in one write and empty the vector. Answers how many bytes were written. |
| `termEditLoop` | value | `(-> KeyIn LineEd String (Option String))` | `Alloc,IO,Mut` |  | Run the line editor on the terminal with `prompt` until Enter or end of input. Answers the line, or `None` when the input closed. |

## `Utf8`

`stdlib/Utf8.ax` — 14 public names

Utf8 - the character layer over `Str`'s bytes.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `utf8IsCont` | value | `(-> Int Bool)` |  |  | Is `b` a continuation byte, `10xxxxxx`? |
| `utf8SeqLen` | value | `(-> Int Int)` |  |  | How many bytes the sequence beginning with lead byte `b` occupies. |
| `utf8DecodeAt` | value | `(-> String Int (Option Int))` |  |  | The code point whose encoding begins at byte offset `i`, or `None` when there is none there. |
| `utf8Next` | value | `(-> String Int Int)` |  |  | The byte offset of the character after the one beginning at `i`, clamped to the byte length as `utf8Offset` is. |
| `utf8Len` | value | `(-> String Int)` |  |  | The number of code points in `s`. |
| `utf8Offset` | value | `(-> String Int Int)` |  |  | The byte offset at which character `n` begins, or the byte length of `s` when there are fewer than `n` characters. |
| `utf8CharAt` | value | `(-> String Int (Option Int))` |  |  | Character `n` of `s`, counting from 0, or `None` past the end or at a byte that is not well-formed UTF-8. |
| `utf8Slice` | value | `(-> String Int Int String)` | `Alloc,Mut` |  | `count` characters of `s` beginning at character `start`, as a `Str` sharing the original's bytes - the character-indexed counterpart of `strSlice`. |
| `utf8Replacement` | value | `Int` |  |  | U+FFFD REPLACEMENT CHARACTER, what a code point that cannot be encoded becomes. |
| `utf8Width` | value | `(-> Int Int)` |  |  | How many bytes code point `cp` occupies when encoded - counting what `utf8FromChar` will actually write, so the two never disagree. |
| `utf8FromChar` | value | `(-> Int String)` | `Alloc,Mut,Unsafe` |  | A freshly allocated `Str` holding `cp` alone. |
| `utf8PushChar` | value | `(-> StrBuilder Int StrBuilder)` | `Alloc,Mut` |  | Append `cp` to `b`, UTF-8 encoded, and answer `b`. It writes the bytes `utf8FromChar` would answer, U+FFFD included, without allocating a `String` for them. A `Char` is a code point, so `as` turns one into the `Int` this takes: `'é'` is 233, two bytes. |
| `utf8Valid` | value | `(-> String Bool)` |  |  | Is every byte of `s` part of a well-formed UTF-8 sequence? |
| `utf8WellFormedAt` | value | `(-> String Int Int Int)` |  |  | The length of the WELL-FORMED UTF-8 sequence that begins at byte `i` of `s` and ends at or before byte `end`: 1 to 4, or 0 when the bytes there are not one. |

## `Uuid`

`stdlib/Uuid.ax` — 19 public names

Uuid - universally unique identifiers, RFC 9562 versions 4 and 7.

    (uuidV4)                          ; (Ok <random uuid>)
    (uuidV7)                          ; (Ok <time-ordered uuid>)
    (uuidToString u)                  ; "xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx"
    (uuidParse "550e8400-e29b-41d4-a716-446655440000")  ; (Ok u)
    (uuidV4Seeded 42)                 ; one fixed uuid, every run

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `uuidInvalidFormat` | value | `Int` |  |  | Text that is not a canonical uuid, or bytes that are not 16 long. |
| `uuidClockUnavailable` | value | `Int` |  |  | This target has no realtime clock, or reading it failed, so a version 7 uuid cannot be stamped. |
| `Uuid` | struct |  |  |  | A universally unique identifier. Make one with `uuidV4`, `uuidV7`, `uuidParse`, `uuidFromBytes` or a seeded constructor, and the all zero value with `uuidNil`. |
| `uuidNil` | value | `Uuid` | `Alloc` |  | The all-zero uuid. |
| `uuidIsNil` | value | `(-> Uuid Bool)` |  |  | Whether `u` is the all-zero uuid. |
| `uuidVersion` | value | `(-> Uuid Int)` |  |  | The version field: 4 or 7 for a value this module generated, 0 for `uuidNil`, and whatever a parsed or injected value carries. |
| `uuidCompare` | value | `(-> Uuid Uuid Int)` |  |  | -1, 0 or 1 as `a` sorts before, equal to or after `b`, comparing the 16 bytes as one unsigned number. Version 7 values sort by timestamp under this order. |
| `uuidEq` | value | `(-> Uuid Uuid Bool)` |  |  | Whether `a` and `b` are the same uuid. |
| `uuidTimestampMs` | value | `(-> Uuid (Option Int))` | `Alloc,Mut,Unsafe` |  | The Unix millisecond timestamp of a version 7 uuid, as `(Some ms)`. Any other version answers `None`. |
| `uuidBytes` | value | `(-> Uuid String)` | `Alloc,Mut,Unsafe` |  | The 16 bytes of `u`, most significant first. |
| `uuidFromBytes` | value | `(-> String (Result Uuid Error))` | `Alloc` |  | The uuid whose bytes are `b`, or `Err` (`uuidInvalidFormat`) when `b` is not 16 bytes. The bytes are taken as they are: no version or variant bits are set, so `uuidFromBytes (uuidBytes u)` is `u` for every `u`. Use `uuidV4FromBytes` or `uuidV7FromBytes` to stamp a version onto bytes from another source. |
| `uuidV4FromBytes` | value | `(-> String (Result Uuid Error))` | `Alloc,Mut` |  | A version 4 uuid over 16 bytes the caller supplies - its own randomness, a recording, a test vector. Only the version and variant bits change. `Err` when `b` is not 16 bytes. |
| `uuidV7FromBytes` | value | `(-> Int String (Result Uuid Error))` | `Alloc,Mut,Unsafe` |  | A version 7 uuid for Unix millisecond `ms` over bytes the caller supplies. The timestamp replaces the first six bytes and the version and variant bits are stamped; the rest is the caller's. `ms` is taken modulo 2^48. `Err` when `b` is not 16 bytes. |
| `uuidToString` | value | `(-> Uuid String)` | `Alloc,Mut,Unsafe` |  | `u` in canonical text form, lower case: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx". |
| `uuidParse` | value | `(-> String (Result Uuid Error))` | `Alloc,Mut,Unsafe` |  | The uuid a canonical text form names, or `Err` (`uuidInvalidFormat`). Upper-case hex is accepted; the hyphenless 32-digit form and the braced form are not. |
| `uuidV4Seeded` | value | `(-> Int Uuid)` | `Alloc,Mut` |  | The version 4 uuid a seed names: the same seed gives the same uuid on every run and target, which is what a test wants. A seed is not entropy - reach for `uuidV4` outside tests. |
| `uuidV7Seeded` | value | `(-> Int Int Uuid)` | `Alloc,Mut` |  | The version 7 uuid a seed names, stamped with Unix millisecond `ms`. Deterministic, like `uuidV4Seeded`. |
| `uuidV4` | value | `(Result Uuid Error)` | `Alloc,Entropy,IO,Mut` |  | A random version 4 uuid, from the kernel's entropy source. |
| `uuidV7` | value | `(Result Uuid Error)` | `Alloc,Entropy,IO,Mut` |  | A time-ordered version 7 uuid: the realtime clock's millisecond, with random bits below it. Two made in the same millisecond differ but do not sort in creation order. |

## `Vec`

`stdlib/Vec.ax` — 16 public names

Vec - a growable array of machine words, in Axiom.

| Name | Kind | Type | Effects | Contracts | Summary |
|---|---|---|---|---|---|
| `vecNew` | value | `(Vec a)` | `Alloc,Mut` |  | An empty `Vec` with `vecDefaultCap` capacity. |
| `vecWithCapacity` | value | `(-> Int (Vec a))` | `Alloc,Mut` |  | An empty `Vec` that can hold at least `cap` elements without growing. |
| `vecOwnsRefs` | value | `(-> (Vec a) Bool)` |  |  | Whether the vector holds a share of every element, which it does when its elements are a counted type (kind 1 in the module comment). |
| `vecLen` | value | `(-> (Vec a) Int)` |  |  | How many elements the vector holds. |
| `vecCap` | value | `(-> (Vec a) Int)` |  |  | How many elements the vector can hold before it grows. |
| `vecGet` | value | `(-> (Vec a) Int a)` | `Unsafe` |  | The element at `i`. REFUSES an index outside `0 .. (vecLen v) - 1`. |
| `vecTry` | value | `(-> (Vec a) Int (Option a))` | `Alloc,Unsafe` |  | The element at `i`, or `None` when there is no element at `i`. |
| `vecSet` | value | `(-> (Vec a) Int a (Vec a))` | `Mut` |  | Overwrite the element at `i`. Returns the handle. |
| `vecPush` | value | `(-> (Vec a) a (Vec a))` | `Alloc,Mut` |  | Append `x`, growing the vector if it is full. Answers `v`. |
| `vecPop` | value | `(-> (Vec a) a)` | `Mut,Unsafe` |  | Remove and return the last element. REFUSES an empty vector. |
| `vecLast` | value | `(-> (Vec a) a)` |  |  | The last element without removing it. REFUSES an empty vector. |
| `vecClear` | value | `(-> (Vec a) (Vec a))` | `Mut` |  | Drop every element, keeping the capacity. Returns the handle. |
| `vecSum` | value | `(-> (Vec Int) Int)` |  |  | The sum of every element. |
| `vecHash` | value | `(-> (Vec Int) Int)` |  |  | A position-sensitive digest of the whole vector. |
| `vecSort` | value | `(-> (Vec Int) (Vec Int))` | `Mut` |  | Sort a vector of `Int` ascending, in place. Answers the vector. |
| `vecSortBy` | value | `(-> (Vec a) (-> a a Int) (Vec a))` | `Alloc,Mut (incomplete)` |  | Sort `v` in place by `cmp`, which takes two elements and answers negative, zero or positive the way `strCmp` does. Answers the vector. `(vecSortBy names (lambda (a b) (strCmp a b)))` orders strings by their bytes. |

