# Tutorial: from a grammar to a tree you can use

hbnf turns a grammar into a parser **and the types of the tree it builds**, in C, Zig,
Rust or Ada.  You write the grammar; you do not write a lexer, a `%union`, a
semantic action for each rule, or the code that builds the tree.  This page takes one small
grammar all the way: write it, generate the parser, read some text, use the tree, make a
mistake and read the error message.

Every program here is a file in `tutorial/`, and `sh tests/tutorial.sh` builds and runs
all of them, so what is printed below is what happens.  (To build `hbnf` itself, see
[Building](README.md#building).)

## 1. The grammar

`tutorial/shopping.hbnf`:

```
prefix none
list = 1*item
item = "buy" qty name [ "from" shop ] ";"
qty  = int
name = word
shop = word
```

It reads

```
buy 2 apples;
buy 1 milk from corner-shop;
```

Six lines, and the whole of the work.  Read it as BNF with ABNF's repetition:

* `"buy"` is text that must be there.  Text is *not* kept in the tree: the grammar already
  says it is there.
* `1*item` is one or more `item`s.  A rule that is a repetition is a **list**.
* `qty = int` makes a **field** called `qty` that holds a number.  *What the tree keeps is
  what the grammar names*: a rule you name and use is a field; a literal is not.
* `[ "from" shop ]` is optional.  An optional part is a list of zero or one.
* `int` and `word` are built in (a number and a bare word).  `str` is a quoted string.
* `prefix none` leaves the generated names as the grammar spells them (the default is
  `bnf_`, so that a generated file cannot clash with your code).

Blanks and line ends between things are skipped.  `whitespace none` says they are not.

## 2. Generate the parser

```
hbnf shopping.hbnf --backend=c    > shopping.c
hbnf shopping.hbnf --backend=zig  > shopping.zig
hbnf shopping.hbnf --backend=rust > shopping.rs
hbnf shopping.hbnf --backend=ada --package=Shopping > shopping.ada    # gnatchop -w splits it
```

One file in C, Zig and Rust.  Nothing to link: `#include "shopping.c"`,
`@import("shopping.zig")`, `mod shopping;`, `with Shopping.Parser;`.

## 3. Read text and use the tree

The same program in four languages.  Each prints

```
2 x apples
1 x milk (from corner-shop)
total: 3 items
```

### C (`tutorial/main.c`)

```c
#include <stdio.h>
#include "shopping.c"

static void add_up(const void *node, node_kind_t kind, void *ctx) {
    if (kind == NODE_ITEM)
        *(long long *)ctx += ((const item_t *)node)->qty;
}

int main(void) {
    const char *text = "buy 2 apples;\nbuy 1 milk from corner-shop;\n";
    struct list_list list;
    char err[512];
    size_t line, col;

    if (!parse_text(text, &list, err, sizeof err, &line, &col)) {
        fprintf(stderr, "%s\n", err);          /* the message points at the text */
        return 1;
    }
    for (const list_t *n = list.head; n; n = n->_link) {
        printf("%lld x %s", n->item.qty, n->item.name);
        if (n->item.item_1.head)                /* [ "from" shop ] is a list of 0 or 1 */
            printf(" (from %s)", n->item.item_1.head->shop);
        printf("\n");
    }
    long long total = 0;
    visit_list(&list, add_up, &total);          /* every node, parent before children */
    printf("total: %lld items\n", total);
    return 0;
}
```

A list is a linked list (`head`, each node's `_link`).  The root is `struct list_list`, because
the first rule is the root.

### Zig (`tutorial/main.zig`)

```zig
const list = shopping.parse_text(a, text, &err, &line, &col) catch {
    std.debug.print("{s}\n", .{std.mem.sliceTo(&err, 0)});
    return;
};
for (list) |*item| {
    std.debug.print("{d} x {s}", .{ item.qty, item.name });
    for (item.item_1) |*from| std.debug.print(" (from {s})", .{from.shop});
    std.debug.print("\n", .{});
}
var total = Total{};
for (list) |*item| shopping.visit_item(item, &total);
```

A list is a slice, `parse_text` takes an allocator (an arena frees the lot), and
`visit_item` calls the `visit_<rule>` methods of any struct you give it.

### Rust (`tutorial/main.rs`)

```rust
let list = match parse_text(text) {
    Ok(l) => l,
    Err(e) => { eprintln!("{}", e.msg); return; }
};
for item in &list {
    print!("{} x {}", item.qty, item.name);
    for from in &item.item_1 { print!(" (from {})", from.shop); }
    println!();
}
let mut total = Total(0);                 // impl Visitor for Total { fn visit_item(..) }
for item in &list { visit_item(item, &mut total); }
```

A list is a `Vec`; nothing to free.

### Ada (`tutorial/main.adb`)

```ada
declare
   List : List_Type := Parse_Text (Text);
begin
   for Item of List loop
      Put (Img (Item.Qty) & " x " & To_String (Item.Name));
      for From of Item.Item_1 loop
         Put (" (from " & To_String (From.Shop) & ")");
      end loop;
      New_Line;
   end loop;
   Free_List (List);                      --  give back what the parse allocated
end;
exception
   when E : Parse_Error => Put_Line (Ada.Exceptions.Exception_Message (E));
```

A list is an `Ada.Containers.Vectors` vector; `Parse_Error` carries the message.

## 4. What every backend gives you

The same shape comes out of the same grammar in all four languages:

| | C | Zig | Rust | Ada |
|---|---|---|---|---|
| read text | `parse_text (text, &out, err, errlen, &line, &col)` | `parse_text (alloc, text, &err, &line, &col)` | `parse_text (text)` | `Parse_Text (Text)` |
| a rule with parts | `struct` | `struct` | `struct` | `record` |
| `*x` and `1*x` | linked list | slice | `Vec` | vector |
| `[ x ]` | list of 0 or 1 | slice of 0 or 1 | `Vec` of 0 or 1 | vector of 0 or 1 |
| a rule that is `a / b` of literals | `enum` | `enum` | `enum` | enumeration |
| visit, parent before children | `visit_<rule>` | `visit_<rule>` | `visit_<rule>` (`Visitor`) | none yet |
| rebuild, children first | `map_<rule>` | `fold_<rule>` | `fold_<rule>` (`Folder`) | none yet |
| release | arena / `free_<rule>` | `deinit_<rule>` | drop | `Free_<Rule>` |
| error | text, line, column | text, line, column | `ParseError { line, col, msg }` | `Parse_Error` |

The messages are the same in all four (section 6).

## 5. Tools that work on any tree (C)

In C, `--ast` adds a few tables and one small walker that knows nothing of your grammar, so
you can write code once and use it on a tree of any grammar:

| flag | adds |
|---|---|
| `--ast` | `walk_<root>` (`node_walk`): enter and leave every node, and answer `WALK_CONTINUE`, `WALK_SKIP` or `WALK_STOP`; `node_kind_name`, `node_alt`, `node_alt_name` say what a node is and which alternative it took |
| `--ast-tools` | `node_kids` (the members of a node), `dump_<root>` (an S-expression), `node_equal` |
| `--spans` | `node_span` (where a node is in the text, in bytes), `node_where` (byte to line and column) |
| `--parents` | `node_parent` |
| `--writer` | `write_<root>`: the tree as text again |

`tutorial/generic.c` uses four of them, on the same list:

```c
int depth = 0;
walk_list(&list, show, &depth);               /* show() prints kind and bytes */
dump_list(&list, buf, n + 1);                 /* an S-expression */
node_where(text, list.head->_link->_pos, &line, &col);
write_list(&list, out, sizeof out);           /* the tree, as text */
```

```
list  bytes 0-13
  item  bytes 0-13
list  bytes 14-42
  item  bytes 14-42
    item_1  bytes 25-41
(list (list item=(item qty=2 name="apples")) (list item=(item qty=1 name="milk" item_1[0]=(item_1 shop="corner-shop"))))
the second item starts at line 2, column 1
written: buy 2 apples;buy 1 milk from corner-shop;
```

The writer is canonical, not pretty: it writes the literals the grammar has, the tokens the
tree holds, and a blank only where two things would otherwise run together.  Zig, Rust and
Ada have a writer for a subset (`--writer`, [WIRE.md](WIRE.md)); the walker, dump, spans
and parents are C only so far.

## 6. Errors

An error says where, what could have stood there, and what did, and points:

```
1:5:4: expected a number, found two
  buy two apples;
      ^
```

and, for `buy 2 apples` with the `;` forgotten, the next line starting too soon:

```
2:1:13: expected one of `from`, `;`, found buy
  buy 1 milk;
  ^
```

The first thing on the line is `LINE:COLUMN:OFFSET:`, the way a compiler writes it: lines and
columns count from 1, the offset is bytes from 0 (in a parser that reads a file one statement
at a time, from the statement's start).  `sed`, `cut`, `tail` and an editor take it as it is:

```sh
msg=$(./prog list.txt 2>&1 | head -1)         # 2:1:13: expected one of ...
line=${msg%%:*}
rest=${msg#*:}; col=${rest%%:*}
rest=${rest#*:}; off=${rest%%:*}
sed -n "${line}p" list.txt                    # the line:   buy 1 milk;
tail -c +$((off + 1)) list.txt | head -c 10   # from the error:   buy 1 milk
```

Put the file name in front and it is `file:2:1:13: ...`, which editors and `grep -n`-style
tools already read.

When a construct that takes more than a couple of lines is left open, the message also says
where it began:

```
13:1:162: expected `'END'`, found end of input
  1:1:0: the block that begins here is not finished:
  'BEGIN'
  ^
```

## 7. Where next

* The notation, every operator and directive: [ABNF.md](ABNF.md).
* Text and bits in one grammar (a protocol with a header and a payload): [WIRE.md](WIRE.md).
* Two real grammars in full, checked against other parsers: `corpus/json`, `corpus/mustache`.
* A language: `corpus/algol60`.
* Why: [WHY.md](WHY.md); the plan and what is not built yet: [RFCPLAN.md](RFCPLAN.md).
