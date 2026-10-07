# AXQL

AXQL is the query language of AXQLite, Axiom's embedded database. This
page defines it: its words, its values and types, its expressions, and
every statement, each shown as text and as the Axiom form the `axql`
macros write. [axqlite.md](axqlite.md) is the guide to using a
database from a program.

## At a glance

Here is a table made, filled and queried, first with the macros and
then with the same statements as text:

```scheme
(import IO)
(import Err)
(import Axqlite)
(import Axqlite.Value)

(:: show (-> (Result Rows Error) Int))
;@axiom:effect(io)
(fn (show r)
  (match r
    ((Ok rs)
      {
        (for row in rs.rows
          (println (unwrapOr (rowTextNamed row "name") "?")))
        0
      })
    ((Err e) (println (errorText e)))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (axqOpen "glance.db" openOptions)
    ((Err e) (println (errorText e)))
    ((Ok db)
      (let ((minAge 30))
        {
          (let ((_ (axqRunOn db (axqlCreateTable IF NOT EXISTS people (id INTEGER PRIMARY KEY) (name TEXT NOT NULL) (age INTEGER))))) 0)
          (let ((_ (axqRunOn db (axqlInsert people (name age) (values (text "Ada") (int 36)) (values (text "Bob") (int 24)))))) 0)
          (show (axqQueryOn db (axqlSelect people (name) (where (> age (int minAge))) (orderBy name))))
          (let ((_ (axqExec db "INSERT INTO people (name, age) VALUES ('Cy', 41)"))) 0)
          (show (axqQueryOn db (Query "SELECT name FROM people WHERE age > ? ORDER BY name" (vec1 (VInt minAge)))))
          (let ((_ (axqClose db))) 0)
        }))))

(:: vec1 (-> Value (Vec Value)))
(fn (vec1 v)
  (let ((out vecNew))
    {
      (vecPush out v)
      out
    }))
```

```text
Ada
Ada
Cy
```

The macro `(axqlSelect people (name) (where (> age (int minAge))) (orderBy name))`
expands to the text `SELECT name FROM people WHERE age > ? ORDER BY name`
with `minAge` bound to its `?`, so both queries run the same statement.

## Words and names

Keywords may be written in any case: `select`, `SELECT` and `Select`
are one word. These words are reserved, and can be a name only in
double quotes:

```text
AND AS BEGIN BY COMMIT CREATE DELETE DROP EXISTS FALSE FROM IF INDEX
INSERT INTO IS LIMIT NOT NULL OFFSET ON OR ORDER PRIMARY ROLLBACK
SELECT SET TABLE TRUE UNIQUE UPDATE VALUES WHERE
```

`INTEGER`, `REAL`, `TEXT`, `BLOB`, `KEY`, `ASC`, `DESC` and
`TRANSACTION` are keywords only where the grammar expects them, so a
column may be called `text` or `key`.

A name is `[A-Za-z_][A-Za-z0-9_]*`, or any text in double quotes, where
`""` stands for one quote: `"order"`, `"first name"`. Names compare
without regard to ASCII case, so `Users`, `users` and `"USERS"` are one
table. A result column keeps the spelling the statement used.

`--` starts a comment that runs to the end of the line. A statement may
end with one `;`. Whitespace separates words and means nothing else.

## Literals

| Literal | Type | Examples |
|---|---|---|
| digits | INTEGER | `0`, `42`, `007` |
| digits with a point, an exponent or both | REAL | `1.5`, `.5`, `5.`, `1e3`, `2.5E-4` |
| text in single quotes, `''` for a quote | TEXT | `'Ada'`, `''`, `'it''s'` |
| `X'` or `x'`, an even number of hex digits, `'` | BLOB | `x''`, `X'00FF'` |
| `NULL` | none | `NULL` |
| `TRUE`, `FALSE` | INTEGER | `1` and `0` |

An integer literal must fit in 64 bits. `-9223372036854775808` is read
as the most negative `INTEGER`; anywhere else, `9223372036854775808` is
`axqSyntax`. A `REAL` literal is read exactly, rounded to the nearest
binary64 value, so `1e309` is infinity. A literal's minus sign is an
operator: `- 5` and `-5` are the same expression.

## Parameters

A statement's values can be left as parameters and bound when it runs:

| Written | Is parameter |
|---|---|
| `?` | one more than the largest number used so far |
| `?N` | number `N`, from 1 to 32766 |
| `:name` | one number per name, in order of first appearance |

So `SELECT ?, ?5, ?` takes parameters 1, 5 and 6, and `:a, :b, :a`
takes two. A statement uses positional parameters or named ones, never
both: mixing them is `axqSyntax`. The values come as a `(Vec Value)`,
the first for parameter 1. `axqParamIndex` answers where a named one
goes, and the wrong number of values is `axqMisuse`.

A parameter is a value, never text: `'x'); DROP TABLE t; --` bound to
`?` is a `TEXT` value like any other. A `REAL` parameter that is a NaN is
refused with `axqType`.

## Types

Every value has one of five types:

| Type | Holds |
|---|---|
| INTEGER | a 64-bit signed integer |
| REAL | an IEEE 754 binary64 number, never NaN |
| TEXT | bytes, conventionally UTF-8 |
| BLOB | bytes |
| NULL | no value |

A column is declared `INTEGER`, `REAL`, `TEXT` or `BLOB`, and holds values of
that type or NULL, nothing else. A `REAL` column also takes an `INTEGER`,
stored as the nearest `REAL`. Nothing converts `TEXT` to a number or a
number to `TEXT`.

Every expression has a type the statement knows before it reads a row,
from its columns' declared types and its parameters' values. A
statement that combines types no operator allows, or stores a value in
a column that can't hold it, answers `axqType` before it reads or
changes anything, even when the table is empty.

## Expressions

From loosest to tightest:

| Operators | Group |
|---|---|
| `OR` | from the left |
| `AND` | from the left |
| `NOT` | prefix |
| `=` `==` `!=` `<>` `IS NULL` `IS NOT NULL` | from the left |
| `<` `<=` `>` `>=` | from the left |
| `+` `-` | from the left |
| `*` `/` `%` | from the left |
| unary `-` | prefix |

Parentheses group as usual. An expression is a literal, a column name,
a parameter, or operators over those. There are no function calls.

### Arithmetic

`+ - * /` take two numbers. Two INTEGERs give an `INTEGER`, and anything
with a `REAL` gives a `REAL`. `%` takes two INTEGERs. NULL on either side
gives NULL.

`INTEGER` arithmetic never wraps. A result outside 64 bits is
`axqArithmetic`, and so is dividing by zero. `/` truncates toward zero
and `%` takes the sign of its left side: `-7 / 2` is `-3` and `-7 % 2`
is `-1`.

`REAL` arithmetic is IEEE 754, so `1e308 * 10` is infinity, except that
dividing by zero and a result that isn't a number (infinity minus
infinity) are `axqArithmetic`.

### Comparison

The six comparisons answer 1, 0, or NULL when either side is NULL.
Numbers compare by value, `INTEGER` against `REAL` exactly: `2 = 2.0` is 1
and `9007199254740993 = 9007199254740992.0` is 0. `TEXT` compares with
`TEXT` and `BLOB` with `BLOB`, byte by byte, a shorter prefix first. Any other
pair is `axqType`.

`e IS NULL` is 1 when `e` is NULL and 0 otherwise; `IS NOT NULL` is the
reverse. They never answer NULL.

### Truth

A number is `TRUE` when it isn't zero, and NULL is NULL. `NOT` gives 0
for `TRUE`, 1 for `FALSE` and NULL for NULL. `AND` is `FALSE` when either side
is `FALSE`, and `OR` is `TRUE` when either side is `TRUE`; otherwise either
gives NULL if either side is NULL. `TEXT` and `BLOB` aren't truth values.

`AND` and `OR` don't depend on the order of their sides. When one side
decides the answer, the other side's failure doesn't matter: in
`b != 0 AND a / b > 1`, a row with `b` 0 is `FALSE`, not a division by
zero, and so is the same condition written the other way round.

### When expressions run

A subexpression that names no column is worked out once, when the
statement starts, before any row is read. So `WHERE a = 1 / 0` fails
even on an empty table. The largest such subexpression is taken whole:
`0 AND 1 / 0` is 0.

A `WHERE` clause is split into its top-level `AND` terms. A row is left
out as soon as any term is `FALSE` or NULL, whatever the others would do,
and a term's failure stops the statement only for a row no term leaves
out.

The select list runs only for the rows returned, after `ORDER BY`,
`LIMIT` and `OFFSET`. `ORDER BY` terms run for every row `WHERE` keeps.

## Statements

A statement is one of these. The macro spelling beside each is what
`Axqlite.AxqlMacro` provides; see [Statements as Axiom forms](#statements-as-axiom-forms).

### `CREATE TABLE`

```text
CREATE TABLE [IF NOT EXISTS] name ( column , ... )
column := name type [NOT NULL] [PRIMARY KEY]
type   := INTEGER | REAL | TEXT | BLOB
```

```scheme fragment
(axqlCreateTable IF NOT EXISTS people (id INTEGER PRIMARY KEY) (name TEXT NOT NULL) (age INTEGER))
```

`NOT NULL` and `PRIMARY KEY` may come in either order. One `INTEGER`
column may be the `PRIMARY KEY`, and is then the row's rowid (see
[Rowids](#rowids)). Column names must differ.

With `IF NOT EXISTS`, a table that already exists makes the statement
do nothing. A name an index already uses, or an existing table without
`IF NOT EXISTS`, is `axqSchema`.

### `DROP TABLE`

```text
DROP TABLE [IF EXISTS] name
```

```scheme fragment
(axqlDropTable IF EXISTS people)
```

Removes the table, its rows and its indices. A table that doesn't exist
is `axqSchema`, unless `IF EXISTS` is written.

### `CREATE INDEX`

```text
CREATE [UNIQUE] INDEX [IF NOT EXISTS] name ON table ( column , ... )
```

```scheme fragment
(axqlCreateIndex UNIQUE IF NOT EXISTS peopleByName ON people (name))
```

An index keeps the table's rows in the order of its columns, for the
lookups described in [How rows are found](#how-rows-are-found). A
`UNIQUE` index refuses a second row with the same values in all its
columns, with `axqConstraint`; a row with NULL in any of them never
conflicts. Creating a `UNIQUE` index over rows that already repeat a value
is `axqConstraint`, and creates nothing.

Tables and indices share one namespace. A name already used, a missing
table, a missing column or a column named twice is `axqSchema`.

### `DROP INDEX`

```text
DROP INDEX [IF EXISTS] name
```

```scheme fragment
(axqlDropIndex peopleByName)
```

### `INSERT`

```text
INSERT INTO table [( column , ... )] VALUES ( expr , ... ) , ...
```

```scheme fragment
(axqlInsert people (name age) (values (text "Ada") (int 36)) (values (text "Bob") null))
(axqlInsert people * (values null (text "Cy") (int 41)))
```

Without a column list, each row gives every column in order. With one,
the columns it leaves out are NULL. Every row gives one value per
column, or the statement is `axqSchema`; every row of one `VALUES` has the
same length, or it is `axqSyntax`. `VALUES` can't name a column.

A row that gives no rowid gets the largest rowid in the table plus one,
or 1 in an empty table. Each row is checked before it is written: its
types, `NOT NULL`, its rowid and every `UNIQUE` index. A row that fails
fails the whole statement, and none of its rows stay.

### `UPDATE`

```text
UPDATE table SET column = expr , ... [WHERE expr]
```

```scheme fragment
(axqlUpdate people (assign (age (+ age (int 1)))) (where (= name (text "Ada"))))
```

The rows `WHERE` matches are found first, then changed one at a time,
each with every `SET` expression worked out over its old values. So
`UPDATE t SET id = id + 100` moves every row once, whatever order the
new rowids fall in. Each row is checked before it is written, as `INSERT`
checks one, and a failure leaves the table as it was. Setting the rowid
or the `INTEGER PRIMARY KEY` moves the row.

### `DELETE`

```text
DELETE FROM table [WHERE expr]
```

```scheme fragment
(axqlDelete people (where (< age (int 18))))
```

The rows `WHERE` matches are found first, then removed with their index
entries.

### `SELECT`

```text
SELECT * | item , ... [FROM table] [WHERE expr]
       [ORDER BY term , ...] [LIMIT expr [OFFSET expr]]
item := expr [AS name]
term := expr [ASC | DESC]
```

```scheme fragment
(axqlSelect people (name (as (* age (int 12)) months)) (where (isNotNull age)) (orderBy (age desc) name) (limit 10) (offset 20))
```

A result column is named by its `AS`, else by the column it names, else
by the expression as written. `*` gives the table's columns in order and
needs a `FROM`. A `SELECT` with no `FROM` answers one row of expressions over
no columns.

`ORDER BY` sorts by each term in turn, ascending unless `DESC` is written.
NULL comes before every value going up and after every value going
down. Numbers come before `TEXT` and `TEXT` before `BLOB`. Rows equal on every
term come in rowid order, so the order of the result is always defined.

A term that is a whole-number literal `k` means the `k`th result column,
from 1. A term that is a bare name matching a result column's `AS` means
that column. Anything else is an expression over the table.

`LIMIT` and `OFFSET` take an `INTEGER` from 0 up, which may be a parameter
and names no column; anything else is `axqType`. `OFFSET` skips rows
before `LIMIT` counts them, and needs a `LIMIT`.

### `BEGIN`, `COMMIT`, `ROLLBACK`

```text
BEGIN [TRANSACTION]
COMMIT [TRANSACTION]
ROLLBACK [TRANSACTION]
```

`BEGIN` opens a transaction and `COMMIT` or `ROLLBACK` ends it. Inside a
transaction a statement that fails is undone on its own and the
transaction stays open. `BEGIN` inside a transaction, or `COMMIT` or
`ROLLBACK` outside one, is `axqMisuse`. [axqlite.md](axqlite.md) covers
transactions from the API.

## Rowids

Every table has a rowid, a 64-bit `INTEGER` that is unique in the table
and never NULL. Rows are stored in rowid order.

The name `rowid` means it in any statement, unless the table has a
column of that name. A table's `INTEGER PRIMARY KEY` column is the rowid
under its own name: `INSERT INTO t (id) VALUES (7)` gives the row rowid
7, and NULL there asks for the next one, as leaving it out does. A row
whose rowid is taken is `axqConstraint`. When every rowid up to the
largest `INTEGER` is used, a row that needs a new one is `axqTooBig`.

## How rows are found

AXQL chooses how to read a table from the `WHERE` clause's `AND` terms:

1. `rowid = v` or the `INTEGER PRIMARY KEY` `= v` reads one row.
2. An equality on an index's first column reads that stretch of the
   index, a `UNIQUE` index first.
3. A range, `<`, `<=`, `>` or `>=`, on the rowid reads that stretch of
   the table.
4. A range on an index's first column reads that stretch of the index.
5. Otherwise the table is read in rowid order, or in the order an index
   gives when `ORDER BY` names exactly that index's columns.

`v` is anything that names no column. Every row read is still checked
against the whole `WHERE`, so the choice changes how long a statement
takes and never what it answers. When the order rows are read in is
already the order `ORDER BY` asks for, rows go straight out; otherwise
they are collected and sorted.

A `SELECT` without `ORDER BY` answers rows in the order they are read:
rowid order from the table, or index order from an index. Write `ORDER`
`BY` when the order matters.

## Errors

A statement that fails answers one of these codes, and leaves the
database as it was before the statement ran:

| Code | When |
|---|---|
| `axqSyntax` | the text doesn't parse. The message starts with the line and column, in bytes from 1 |
| `axqSchema` | a table, column or index that doesn't exist, one that already does, or a column list that doesn't fit the table |
| `axqType` | a value of the wrong type for a column, an operator, or LIMIT |
| `axqConstraint` | NULL in a NOT NULL column, a rowid already taken, or a value a UNIQUE index already holds |
| `axqArithmetic` | INTEGER overflow, division by zero, or a REAL with no numeric answer |
| `axqMisuse` | transaction statements out of order, or the wrong number of parameters |
| `axqTooBig` | no rowid left, or an index entry longer than 1000 bytes |

`axqBusy`, `axqReadOnly`, `axqIoFailed`, `axqCorrupt` and
`axqNotADatabase` come from the database file rather than the
statement; [axqlite.md](axqlite.md) covers them.

## Statements as Axiom forms

`Axqlite.AxqlMacro` writes each statement as an Axiom form, checked
when the program compiles. A form expands to a `Query`: the
statement's text, spelled one canonical way, and its parameters. The
text parser then reads it like any other, so a form and its text mean
exactly the same thing.

In a form, a bare identifier is a name: a table, a column or an index.
An Axiom value enters only through a marker, and always as a parameter:

| Marker | Binds |
|---|---|
| `(int e)` | `(VInt e)` |
| `(real e)` | `(VReal e)` |
| `(text e)` | `(VText e)` |
| `(blob e)` | `(VBlob e)` |
| `(param v)` | the `Value` `v` |
| `null` | NULL, written into the text |

The operators are `and`, `or`, `not`, `=`, `!=`, `<`, `<=`, `>`, `>=`,
`+`, `-`, `*`, `/`, `%`, `neg` for unary minus, `isNull` and
`isNotNull`, each written in prefix form: `(and (> age (int 18)) (isNull deleted))`.
`and` and `or` take two to eight operands. The canonical text puts an
operand in parentheses only when it is itself an operation, so that
form is `(age > ?) AND (deleted IS NULL)`.

The clauses of `axqlSelect` are `(where e)`, `(orderBy term ...)`,
`(limit n)` and `(offset n)`, in that order and each optional, with `n`
an Axiom `Int`. An `ORDER BY` term is a column, `(column desc)` or
`(column asc)`, or `(desc e)` or `(asc e)` for any expression. A select
list is `*`, one column, or a list of columns and `(as e name)` items.
`UPDATE`'s list is `(assign (column e) ...)`, because `set` is Axiom's own
word.

A form that doesn't fit a statement's shape is a compile error at the
invocation. `axqlTable` goes further and declares a record type with
typed reads and writes for a table; [axqlite.md](axqlite.md) shows it.

Limits, all of the forms rather than of AXQL:

- A form has no number or string literals, because a macro can't tell
  `18` from a column name. A constant goes through a marker.
- A list in a form holds at most 16 items, and `axqlCreateTable` at most
  32 columns. The text has no such limits.
- A name must be an Axiom identifier. A name beginning `axqlArg` can't
  be used in a form.

Tested by `tests/axqlite/620-macro-text.ax` and `tests/axqlite/624-macro-malformed.ax`.

## What AXQL doesn't have

AXQL reads and writes one table per statement. It has no joins, no
subqueries, no aggregates and no `GROUP BY`, no views, triggers, window
functions or virtual tables, and no functions of any kind. There is no
`ALTER TABLE`: drop the table and create it again. There are no default
values, no column-level `UNIQUE` (use a `UNIQUE` index), no collations, and
no conversion between `TEXT` and numbers.

Tested by the scripts in `tests/axqlite/axql/`, run by
`tests/axqlite/500-axql-ddl.ax` and its neighbours.

## See also

- [axqlite.md](axqlite.md): using a database from a program.
- [axqlite-format.md](axqlite-format.md): the file format and what a
  commit guarantees.
