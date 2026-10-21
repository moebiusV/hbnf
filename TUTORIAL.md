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
| walk any tree, `--ast` | `walk_<root>` | `walk_<root>` | `walk_<root>` | `Walk_<Root>` |
| dump any tree, `--ast` | `dump_<root>` | `dump_<root>` | `dump_<root>` | `Dump_<Root>` |
| release | arena / `free_<rule>` | `deinit_<rule>` | drop | `Free_<Rule>` |
| error | text, line, column | text, line, column | `ParseError { line, col, msg }` | `Parse_Error` |

The messages are the same in all four (section 7).

## 5. Your own walker, dump and pretty-printer

Nothing about a tree needs a library.  A walker is a function per rule that visits the
fields in the order the grammar has them; a dump is the same recursion that writes an
S-expression; a pretty-printer is the same recursion that writes the text the grammar
reads, in one layout.  `tutorial/tour.c`, `tour.zig`, `tour.rs` and `tour.adb` are all three, in
each language, over a deliberately messy input (`buy  2   apples ;` and a line broken in the
middle).  In C:

```c
static void my_walk_item(const item_t *item, int depth) {
    printf("%*sitem\n", depth * 2, "");
    printf("%*sqty %lld\n", (depth + 1) * 2, "", item->qty);
    printf("%*sname %s\n", (depth + 1) * 2, "", item->name);
    for (const item_1_t *from = item->item_1.head; from; from = from->_link) {
        printf("%*sfrom\n", (depth + 1) * 2, "");
        my_walk_shop(from->shop, depth + 2);
    }
}

static void my_print_list(const struct list_list *list) {      /* the pretty-printer */
    for (const list_t *n = list->head; n; n = n->_link) {
        printf("buy %lld %s", n->item.qty, n->item.name);
        if (n->item.item_1.head)
            printf(" from %s", n->item.item_1.head->shop);
        printf(";\n");
    }
}
```

and all four print

```
== walk
list
  item
    qty 2
    name apples
  item
    qty 1
    name milk
    from
      shop corner-shop
== dump
(list (item (qty 2) (name "apples")) (item (qty 1) (name "milk") (from (shop "corner-shop"))))
== print
buy 2 apples;
buy 1 milk from corner-shop;
```

The next section is the same thing done once for every grammar, by the generator.

## 6. Tools that work on any tree

`--ast` makes a walker that knows nothing of your grammar, so the code you write for it works on
a tree of any grammar.  The tree is walked as **nodes**: every struct, and every element of a
list, is a node with a kind (the rule's name), the alternative it took if the rule has
alternatives, and its members (`node_kids`).  Four things come with it, in C, Zig, Rust and Ada:

| | C | Zig | Rust | Ada |
|---|---|---|---|---|
| walk: enter and leave every node; skip a subtree; stop | `walk_<root> (&tree, fn, ctx)` | `walk_<root> (tree, &walker, alloc)` | `walk_<root> (&tree, &mut walker)` | `Walk_<Root> (Tree, Walker)` |
| what a node is | `node_kind_name`, `node_alt`, `node_alt_name` | the same | the same | `Node_Kind_Name`, `Node_Alt`, `Node_Alt_Name` |
| its members | `node_kids` | `node_kids` | `node_kids` | `Node_Kids` |
| dump as an S-expression | `dump_<root>` (`--ast-tools`) | `dump_<root>` | `dump_<root>` | `Dump_<Root>` |
| equal when the dumps are | `node_equal` | `node_equal` | `node_equal` | `Node_Equal` |

The dump is the same text in all four languages: `tests/ast.sh` checks the Rust, Zig and Ada
dumps against the C one, character for character.  `tutorial/tools.c`, `tools.zig`, `tools.rs` and
`tools.adb` are the same program; in Rust it is

```rust
struct Show { depth: usize }
impl Walker for Show {
    fn enter(&mut self, n: Node) -> Walk {
        println!("{}{}", "  ".repeat(self.depth), node_kind_name(n));
        self.depth += 1;
        Walk::Continue                    // or Walk::Skip (not the children), Walk::Stop
    }
    fn leave(&mut self, _n: Node) -> Walk { self.depth -= 1; Walk::Continue }
}

walk_list(&list, &mut Show { depth: 0 });
println!("{}", dump_list(&list));
```

and all four print

```
list
  item
list
  item
    item_1
(list (list item=(item qty=2 name="apples")) (list item=(item qty=1 name="milk" item_1[0]=(item_1 shop="corner-shop"))))
```

(The `list` nodes are the list's elements; each holds an `item`.  `item_1` is the optional
`[ "from" shop ]`.)

More, as flags:

| flag | adds |
|---|---|
| `--spans` | `node_span` (where a node is in the text: byte offsets, the blanks before it left out), `node_where` (byte to line and column), in C, Zig, Rust and Ada |
| `--parents` | which node holds each node: `node_parent` in C; `link_<root>` builds a `Parents` and `parent (node)` reads it in Zig, Rust and Ada |
| `--writer` | `write_<root>`: the tree as text again, in C, Zig, Rust and Ada |

`tests/spans.sh` checks that all four print the same places and parents for one tree.  In C
(`tutorial/generic.c`):

```c
int depth = 0;
walk_list(&list, show, &depth);               /* show() prints kind and bytes */
node_where(text, list.head->_link->_pos, &line, &col);
write_list(&list, out, sizeof out);           /* the tree, as text */
```

```
list  bytes 0-13
  item  bytes 0-13
list  bytes 14-42
  item  bytes 14-42
    item_1  bytes 25-41
the second item starts at line 2, column 1
written: buy 2 apples;buy 1 milk from corner-shop;
```

The writer is canonical, not pretty (a `Layout` you give it can change that: it is asked before each token what goes before it, may give other text for it, and is told on entering and leaving each node, in C, Zig, Rust and Ada; `tests/writer/layout_main.*`): it writes the literals the grammar has, the tokens the
tree holds, and a blank only where two things would otherwise run together.  A layout you like
is a pretty-printer of your own (section 5).

## 7. Errors

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

## 8. Where next

* The notation, every operator and directive: [ABNF.md](ABNF.md).
* Text and bits in one grammar (a protocol with a header and a payload): [WIRE.md](WIRE.md).
* Two real grammars in full, checked against other parsers: `corpus/json`, `corpus/mustache`.
* A language: `corpus/algol60`.
* Why: [WHY.md](WHY.md); the plan and what is not built yet: [RFCPLAN.md](RFCPLAN.md).
