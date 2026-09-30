#!/usr/bin/env python3
"""Write the rule tables of stdlib/Axqlite/AxqlMacro.ax.

    python3 tests/axqlite/tools/axql_macros.py            # rewrite the file
    python3 tests/axqlite/tools/axql_macros.py --check    # exit 1 if it differs

The macros take lists (a select list, a row's values, a table's columns)
without using `...`: a form that reaches a template through `...` has
its free names resolved as if the macro had written them, so a variable
inside it is undefined at the call. Each list therefore gets one rule per
length, which is regular enough to write out here rather than by hand.

Everything between the line `; @generated-begin` and `; @generated-end`
in AxqlMacro.ax comes from this script; the rest of the file is
hand-written. Python 3.12 standard library only.
"""
import pathlib
import sys

LIST = 16      # the longest list a form takes
COLUMNS = 32   # the most columns axqlCreateTable takes
FIELDS = 16    # the most fields axqlTable takes

ROOT = pathlib.Path(__file__).resolve().parents[3]
TARGET = ROOT / "stdlib" / "Axqlite" / "AxqlMacro.ax"


def names(prefix, n, start=1):
    return [f"{prefix}{i}" for i in range(start, start + n)]


def block(lines, indent):
    pad = " " * indent
    return "\n".join(pad + l for l in lines)


def joined(calls, sep, indent):
    """Calls separated by `(axqlPut axqlArgQb SEP)`, as block lines."""
    out = []
    for i, c in enumerate(calls):
        if i > 0 and sep is not None:
            out.append(f'(axqlPut axqlArgQb "{sep}")')
        out.append(c)
    return out


def rule(pattern, body_lines, indent=2):
    if len(body_lines) == 1:
        return f"{' ' * indent}(({pattern}) {body_lines[0]})"
    inner = block(body_lines, indent + 4)
    return f"{' ' * indent}(({pattern})\n{' ' * (indent + 2)}{{\n{inner}\n{' ' * (indent + 2)}}})"


def emacro(name, literals, rules, pub=False):
    """A rule list laid out as `axiom fmt` lays it out: one rule per
    line, the first on the head's line unless a literals header is
    there."""
    head = f"({'pub ' if pub else ''}emacro {name}"
    if literals:
        head += f" (literals {' '.join(literals)})"
        return head + "\n" + "\n".join(rules) + ")"
    return head + " " + rules[0].lstrip() + "".join("\n" + r for r in rules[1:]) + ")"


def spread():
    rules = []
    for n in range(LIST + 1, 1, -1):
        a = " ".join(names("axqlArgA", n))
        rules.append(f"  ((axqlSpread axqlArgK axqlArgQb ({a})) (axqlArgK axqlArgQb {a}))")
    rules.append("  ((axqlSpread axqlArgK axqlArgQb axqlArgA1) (axqlArgK axqlArgQb axqlArgA1))")
    return emacro("axqlSpread", [], rules, pub=True)


def list_macro(name, item, sep, head_word=None, max_n=LIST, min_n=1, pub=False):
    """`(name qb [word] x1 .. xn)` writing each item with `item` and
    `sep` between them. Each rule writes its first item and hands the
    rest to the rule one shorter, naming them, so no `...` is used."""
    rules = []
    lits = [head_word] if head_word else []
    for n in range(min_n, max_n + 1):
        xs = names("axqlArgX", n)
        pat = " ".join([name, "axqlArgQb"] + lits + xs)
        if n == 1:
            rules.append(f"  (({pat}) ({item} axqlArgQb {xs[0]}))")
        else:
            rest = " ".join([name, "axqlArgQb"] + lits + xs[1:])
            rules.append(f'  (({pat}) {{ ({item} axqlArgQb {xs[0]}) (axqlPut axqlArgQb "{sep}") ({rest}) }})')
    return emacro(name, lits, rules, pub=pub)


def items_macro():
    """The select list: plain items, or a first `(as e n)` item spread
    in front as `as e n`."""
    rules = ["  ((axqlItems axqlArgQb as axqlArgE axqlArgN) (axqlItem axqlArgQb (as axqlArgE axqlArgN)))"]
    for n in range(1, LIST):
        xs = names("axqlArgX", n, 2)
        pat = " ".join(["axqlItems", "axqlArgQb", "as", "axqlArgE", "axqlArgN"] + xs)
        rest = " ".join(["axqlItems", "axqlArgQb"] + xs)
        rules.append(f'  (({pat}) {{ (axqlItem axqlArgQb (as axqlArgE axqlArgN)) (axqlPut axqlArgQb ", ") ({rest}) }})')
    for n in range(1, LIST + 1):
        xs = names("axqlArgX", n)
        pat = " ".join(["axqlItems", "axqlArgQb"] + xs)
        if n == 1:
            rules.append(f"  (({pat}) (axqlItem axqlArgQb axqlArgX1))")
        else:
            rest = " ".join(["axqlItems", "axqlArgQb"] + xs[1:])
            rules.append(f'  (({pat}) {{ (axqlItem axqlArgQb axqlArgX1) (axqlPut axqlArgQb ", ") ({rest}) }})')
    return emacro("axqlItems", ["as"], rules)


def select_macro():
    w = "(where axqlArgW)"
    lim = "(limit axqlArgN)"
    off = "(offset axqlArgM)"
    o = "axqlArgO"
    where_call = ['(axqlPut axqlArgQb " WHERE ")', "(axqlExpr axqlArgQb axqlArgW)"]
    order_call = ['(axqlPut axqlArgQb " ORDER BY ")', "(axqlSpread axqlOrderTerms axqlArgQb axqlArgO)"]
    limit_call = ['(axqlPut axqlArgQb " LIMIT ")', "(axqlPutParam axqlArgQb (VInt axqlArgN))"]
    offset_call = ['(axqlPut axqlArgQb " OFFSET ")', "(axqlPutParam axqlArgQb (VInt axqlArgM))"]
    # In an order where a literal clause is tried before a binder in the
    # same place, so a binder only ever takes an ORDER BY clause.
    shapes = [
        [],
        [w], [lim],
        [lim, off], [w, lim], [w, o], [o, lim],
        [w, lim, off], [w, o, lim], [o, lim, off],
        [w, o, lim, off],
        [o],
    ]
    rules = []
    for star in (True, False):
        for shape in shapes:
            cols = "*" if star else "axqlArgC"
            pat = " ".join(["axqlSelect", "axqlArgT", cols] + shape)
            body = []
            if star:
                body.append('(axqlPut axqlArgQb "SELECT * FROM ")')
            else:
                body.append('(axqlPut axqlArgQb "SELECT ")')
                body.append("(axqlSpread axqlItems axqlArgQb axqlArgC)")
                body.append('(axqlPut axqlArgQb " FROM ")')
            body.append("(axqlPutName axqlArgQb (syntax/name axqlArgT))")
            for part in shape:
                body += {w: where_call, o: order_call, lim: limit_call, off: offset_call}[part]
            body.append("(axqlFinish axqlArgQb)")
            inner = block(body, 8)
            rules.append(f"  (({pat})\n    (let ((axqlArgQb axqlBuilder))\n      {{\n{inner}\n      }}))")
    doc = """; A SELECT from table `t`: its select list (`*`, one column, or a list
; of columns and `(as e name)` items), then its clauses in this order,
; each optional: `(where e)`, `(orderBy term ...)`, `(limit n)`, and
; `(offset n)` after a `limit`. `n` is an Axiom `Int`, bound as a
; parameter.
;
;     (axqlSelect users * (where (= id (int 7))))
;     (axqlSelect users (name (as (* age (int 12)) months)) (orderBy (name desc)) (limit 5) (offset 10))
"""
    return doc + emacro("axqlSelect", ["*", "where", "limit", "offset"], rules, pub=True)


def insert_macro():
    rules = []
    for star in (True, False):
        for n in range(1, LIST + 1):
            rs = names("axqlArgR", n)
            cols = "*" if star else "axqlArgC"
            pat = " ".join(["axqlInsert", "axqlArgT", cols] + rs)
            packed = "(rows " + " ".join(rs) + ")"
            target = "(axqlInsertAll axqlArgT " + packed + ")" if star else "(axqlInsertInto axqlArgT axqlArgC " + packed + ")"
            rules.append(f"  (({pat}) {target})")
    doc = """; An INSERT into table `t`: `*` for every column in order, or the
; columns the rows fill, then one `(values e ...)` per row, up to 16.
;
;     (axqlInsert users (name age) (values (text n) (int a)) (values (text m) null))
"""
    return doc + emacro("axqlInsert", ["*"], rules, pub=True)


def create_table_macro():
    rules = []
    for ine in (True, False):
        for n in range(1, COLUMNS + 1):
            cs = names("axqlArgC", n)
            pat = " ".join(["axqlCreateTable"] + (["IF", "NOT", "EXISTS"] if ine else []) + ["axqlArgT"] + cs)
            head = "CREATE TABLE IF NOT EXISTS " if ine else "CREATE TABLE "
            rules.append(f'  (({pat}) (axqlCreateTableOf "{head}" axqlArgT (columns {" ".join(cs)})))')
    doc = """; A CREATE TABLE: an optional `IF NOT EXISTS`, the table's name, and
; one `(name TYPE ...)` per column, up to 32.
;
;     (axqlCreateTable IF NOT EXISTS users (id INTEGER PRIMARY KEY) (name TEXT NOT NULL))
"""
    return doc + emacro("axqlCreateTable", ["IF", "NOT", "EXISTS"], rules, pub=True)


def table_macro():
    rules = []
    for n in range(1, FIELDS + 1):
        fs = names("axqlArgF", n)
        ts = names("axqlArgT", n)
        pairs = " ".join(f"({f} {t})" for f, t in zip(fs, ts))
        pat = f"axqlTable axqlArgS axqlArgTbl {pairs}"
        fields = " ".join(f"({f} : {t})" for f, t in zip(fs, ts))
        reads = " ".join(f"(axqlReadField axqlArgRd {f} {t})" for f, t in zip(fs, ts))
        rules.append(f"""  (({pat})
   (pub struct axqlArgS {fields})
   (pub :: (syntax/join rowTo axqlArgS) (-> Row (Result axqlArgS Error)))
   (pub fn ((syntax/join rowTo axqlArgS) axqlArgRow)
     (let ((axqlArgRd (axqlReader axqlArgRow)))
       (axqlReaderDone axqlArgRd (axqlArgS {reads}))))
   (axqlTableRest axqlArgS axqlArgTbl (names {" ".join(fs)}) (types {" ".join(ts)}) (fields {pairs})))""")
    doc = """; A table of typed rows. `(axqlTable User users (id RowId) (name String)
; (age OptInt))` declares, for table `users`:
;
;   struct User          one field per column, of the type given
;   createUserTable      a `Query`: its CREATE TABLE
;   selectAllUser        a `Query`: every row, columns in field order
;   rowToUser row        the `User` a row holds, by column name
;   insertUser db u      insert `u`
;   queryUser db q       run `q` and answer each row as a `User`
;
; A field's type is `Int`, `Float`, `String` or `Bytes` for a NOT NULL
; column of INTEGER, REAL, TEXT or BLOB; `OptInt`, `OptFloat`,
; `OptString` or `OptBytes` for a column that may be NULL, held as an
; `Option`; or `RowId`, an `Int` that is the INTEGER PRIMARY KEY. It
; takes 1 to 16 fields.
"""
    return doc + "(pub macro axqlTable " + rules[0].lstrip() + "".join("\n" + r for r in rules[1:]) + ")"


def field_values_macro():
    rules = []
    for n in range(1, FIELDS + 1):
        ts = names("axqlArgT", n)
        vs = names("axqlArgV", n)
        pat = "axqlFieldValues axqlArgQb (types " + " ".join(ts) + ") " + " ".join(vs)
        first = f"(axqlAddParam axqlArgQb (axqlFieldValue {ts[0]} {vs[0]}))"
        if n == 1:
            rules.append(f"  (({pat}) {first})")
        else:
            rest = "axqlFieldValues axqlArgQb (types " + " ".join(ts[1:]) + ") " + " ".join(vs[1:])
            rules.append(f"  (({pat}) {{ {first} ({rest}) }})")
    return emacro("axqlFieldValues", ["types"], rules, pub=True)


def operand_macro():
    rules = [
        '  ((axqlOperand axqlArgQb null) (axqlPut axqlArgQb "NULL"))',
        "  ((axqlOperand axqlArgQb (int axqlArgE)) (axqlPutParam axqlArgQb (VInt axqlArgE)))",
        "  ((axqlOperand axqlArgQb (real axqlArgE)) (axqlPutParam axqlArgQb (VReal axqlArgE)))",
        "  ((axqlOperand axqlArgQb (text axqlArgE)) (axqlPutParam axqlArgQb (VText axqlArgE)))",
        "  ((axqlOperand axqlArgQb (blob axqlArgE)) (axqlPutParam axqlArgQb (VBlob axqlArgE)))",
        "  ((axqlOperand axqlArgQb (param axqlArgE)) (axqlPutParam axqlArgQb axqlArgE))",
    ]
    for n in range(1, 9):
        form = "(" + " ".join(["axqlArgH"] + names("axqlArgA", n)) + ")"
        rules.append(rule(f"axqlOperand axqlArgQb {form}",
                          ['(axqlPut axqlArgQb "(")', f"(axqlExpr axqlArgQb {form})", '(axqlPut axqlArgQb ")")']))
    rules.append("  ((axqlOperand axqlArgQb axqlArgC) (axqlPutName axqlArgQb (syntax/name axqlArgC))))")
    return "(emacro axqlOperand (literals null int real text blob param)\n" + "\n".join(rules)


BINARY = [("=", "="), ("!=", "!="), ("<", "<"), ("<=", "<="), (">", ">"), (">=", ">="),
          ("+", "+"), ("-", "-"), ("*", "*"), ("/", "/"), ("%", "%")]


def expr_macro():
    rules = []
    for m in ["null", "(int axqlArgE)", "(real axqlArgE)", "(text axqlArgE)", "(blob axqlArgE)", "(param axqlArgE)"]:
        rules.append(f"  ((axqlExpr axqlArgQb {m}) (axqlOperand axqlArgQb {m}))")
    rules.append(rule("axqlExpr axqlArgQb (not axqlArgA)", ['(axqlPut axqlArgQb "NOT ")', "(axqlOperand axqlArgQb axqlArgA)"]))
    rules.append(rule("axqlExpr axqlArgQb (neg axqlArgA)", ['(axqlPut axqlArgQb "-")', "(axqlOperand axqlArgQb axqlArgA)"]))
    rules.append(rule("axqlExpr axqlArgQb (isNull axqlArgA)", ["(axqlOperand axqlArgQb axqlArgA)", '(axqlPut axqlArgQb " IS NULL")']))
    rules.append(rule("axqlExpr axqlArgQb (isNotNull axqlArgA)", ["(axqlOperand axqlArgQb axqlArgA)", '(axqlPut axqlArgQb " IS NOT NULL")']))
    for op, txt in BINARY:
        rules.append(rule(f"axqlExpr axqlArgQb ({op} axqlArgA axqlArgB)",
                          ["(axqlOperand axqlArgQb axqlArgA)", f'(axqlPut axqlArgQb " {txt} ")', "(axqlOperand axqlArgQb axqlArgB)"]))
    for word, txt in [("and", "AND"), ("or", "OR")]:
        for n in range(2, 9):
            xs = names("axqlArgX", n)
            rules.append(rule(f"axqlExpr axqlArgQb ({word} {' '.join(xs)})",
                              joined([f"(axqlOperand axqlArgQb {x})" for x in xs], f" {txt} ", 0)))
    for n in range(1, 9):
        form = "(" + " ".join(["axqlArgH"] + names("axqlArgA", n)) + ")"
        rules.append(f"  ((axqlExpr axqlArgQb {form}) (axqlUnknownOperator axqlArgH))")
    rules.append("  ((axqlExpr axqlArgQb axqlArgC) (axqlPutName axqlArgQb (syntax/name axqlArgC))))")
    lits = "null int real text blob param and or not neg isNull isNotNull " + " ".join(op for op, _ in BINARY)
    return f"(emacro axqlExpr (literals {lits})\n" + "\n".join(rules)


def generate():
    parts = [
        "; ------------------------------------------------------------------\n"
        "; Expressions. `axqlExpr` writes a whole expression; `axqlOperand`\n"
        "; writes an operand, in parentheses when it is itself an operation.\n"
        "; ------------------------------------------------------------------\n" + operand_macro(),
        "\n" + expr_macro(),
        "\n; ------------------------------------------------------------------\n"
        "; Lists. `(axqlSpread k qb (a b c))` is `(k qb a b c)`: a list in\n"
        "; parentheses spread into the arguments of the helper `k` that\n"
        "; writes it, which has one rule per length. A one-item list arrives\n"
        "; as the item itself.\n"
        "; ------------------------------------------------------------------\n" + spread(),
        "\n; Expressions separated by `, `.\n" + list_macro("axqlExprs", "axqlExpr", ", "),
        "\n; Names separated by `, `.\n" + list_macro("axqlNames", "axqlPutNameOf", ", "),
        "\n; The items of a select list. A list whose first item is `(as e n)`\n"
        "; arrives with that item's three parts spread in front, because\n"
        "; `((as e n) b)` and `(as e n b)` are one form.\n" + items_macro(),
        "\n; `(orderBy term ...)`, spread: the word, then the terms.\n"
        + list_macro("axqlOrderTerms", "axqlOrderTerm", ", ", head_word="orderBy"),
        "\n" + select_macro(),
        "\n; `(values e ...)`, spread: one row's values.\n"
        + list_macro("axqlValuesOf", "axqlExpr", ", ", head_word="values"),
        "\n; `(rows r ...)`, spread: each `(values e ...)` in parentheses.\n"
        + list_macro("axqlRows", "axqlRow", ", ", head_word="rows"),
        "\n; `(columns c ...)`, spread: each column definition.\n"
        + list_macro("axqlColumnDefs", "axqlColumnDef", ", ", head_word="columns", max_n=COLUMNS),
        "\n; `(names f ...)`, spread: names separated by `, `. Public, as the\n"
        "; helpers `axqlTable` reaches are, because a declaration macro's\n"
        "; expansion is resolved where it is used.\n"
        + list_macro("axqlFieldNames", "axqlPutNameOf", ", ", head_word="names", max_n=FIELDS, pub=True),
        "\n; `(names f ...)`, spread: one `?` per name.\n"
        + list_macro("axqlMarks", "axqlMark", ", ", head_word="names", max_n=FIELDS, pub=True),
        "\n; `(fields (f t) ...)`, spread: each field as its column.\n"
        + list_macro("axqlFieldColumns", "axqlFieldColumn", ", ", head_word="fields", max_n=FIELDS, pub=True),
        "\n" + insert_macro(),
        "\n; `(assign (column e) ...)`, spread.\n"
        + list_macro("axqlAssigns", "axqlAssign", ", ", head_word="assign"),
        "\n" + create_table_macro(),
        "\n; The typed values of a record's fields, as parameters.\n" + field_values_macro(),
        "\n" + table_macro(),
    ]
    return "\n".join(parts) + "\n"


def main(argv):
    text = TARGET.read_text(encoding="utf-8")
    begin = text.index("; @generated-begin\n") + len("; @generated-begin\n")
    end = text.index("; @generated-end")
    new = text[:begin] + generate() + text[end:]
    if argv and argv[0] == "--check":
        if new != text:
            print("AxqlMacro.ax differs from what axql_macros.py writes")
            return 1
        return 0
    TARGET.write_text(new, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
