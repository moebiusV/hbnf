# id-ref serializer output for the hbnf C backend

Status: implemented as `hbnf_cli --backend=c --idref`, which emits the `id,
parent` fields, one typed wire record per object, a pre-order serializer
(`serialize_tree`) and a decoder that rebuilds the pointer tree
(`decode_<rule>`, strings in the arena, released by the root's `free_`).  The
per-type `*_find()` helpers and the merge side described below are not
generated.  The daemon claims below were verified against the OpenBSD source
tree (bgpd, ospfd, relayd, httpd, ldpd; pfctl as the counter-example).

## Why

The C backend today emits a **pointer-linked** tree: list members are `X_t *`
head pointers, list nodes carry `struct X *next`. That is the right shape for a
single process that owns the whole parse tree.

It is the wrong shape for the privsep daemons the grammars target (bgpd, ospfd,
relayd, httpd, smtpd, ldpd). Those hand the finished config to unprivileged
children over imsg, and a pointer cannot cross that boundary. What actually
crosses is a flat stream of objects that reference each other by **id**
(`objid_t` / `rl_conf.id`), serialized by the parent and rebuilt by each child
into its own pointer/queue-linked tree via per-type `*_find()` helpers.

So an id-ref output should emit three things:

1. flat objects that cross-reference by **id**, not pointer;
2. a **serializer** that walks them into typed records;
3. per-type **find** helpers and, optionally, the rebuild/merge side.

## The two representations (keep them distinct)

* **Wire form** — what this mode emits and what crosses the channel: id-refs
  plus length-prefixed scalar blobs. No pointers, no `next` links.
* **Live form** — what the consumer rebuilds: a conventional `TAILQ`/`RB`/
  pointer tree it allocates itself.

This matches the daemons exactly: "each process has its own separately
allocated tree, and none of them is the parser's original." The generator emits
the wire form; the live form is the consumer's, so it is optional output (the
`config_get*`/`merge_*` helpers).

## The id invariant

Assign ids in **parse (document) order**, monotonically. Then a list field
`*( child )` needs no explicit id array: the children of object *i* are exactly
the `child` objects with `parent == i`, in id order, which is document order.

That is why the daemons store the parent id **on the child** (`relayid`,
`tableid`, `rule_protoid`) instead of a child-id array on the parent: a child
always references a **lower** id — its parent, already received — so
deserialization is single-pass and forward-only. On arrival the child looks up
its parent (present) and links itself into the parent's list.

Caveat: this collapses if a struct has two list members of the same element
type (`x = "a" *( e ) *( e )`), because the parent id alone cannot say which
slot a child belongs to. In that case tag the child with a `slot` (which list
member it is), or fall back to explicit per-list id arrays. None of the nine
daemon grammars hit this today, but the emitter must handle it.

## Generated shape (concrete)

Grammar:

    document = *( node )
    node     = "leaf"  string
             / "group" string "{" *( node ) "}"

Current pointer output (today's `Emit`):

```c
typedef struct node node_t;
struct node     { node_t *next; int kind; char *value; node_t *children; };
typedef struct document document_t;
struct document { node_t *head; };
```

Proposed id-ref output — the flat in-memory table the parser produces (strings
are still `char *` here; only the structural links become ids):

```c
typedef uint32_t objid_t;

enum node_kind { NODE_LEAF = 0, NODE_GROUP = 1 };

struct node {
    objid_t       id;      /* parser-assigned, monotonic */
    objid_t       parent;  /* 0 = top-level */
    enum node_kind kind;
    char         *value;
    /* group children = nodes with parent == this id, in id order */
};

struct document {
    objid_t      *top;     /* ids of top-level nodes, in order */
    size_t        ntop;
};

/* flat ownership table: node[id-1], the serializer's input */
struct config {
    objid_t       next_id;
    struct node **node;
    size_t        nnode;
};
```

The parser's allocation changes from `calloc + link next` to `calloc + assign
id + record parent`; the recursive-descent parse logic is untouched.

## The serializer

Walk the table in id order and emit one typed record per object: id + scalars +
referenced ids, with string blobs length-prefixed. Ids serialize trivially; a
`char *` does not.

```c
struct node_msg { objid_t id, parent; uint32_t kind, vlen; };

void serialize_config(struct config *c,
                      void (*emit)(uint32_t type, const void *p, size_t n))
{
    for (size_t i = 0; i < c->nnode; i++) {
        struct node   *n = c->node[i];
        struct node_msg m = { n->id, n->parent, n->kind,
                              (uint32_t)strlen(n->value) };
        emit(IMSG_NODE, &m, sizeof m);
        emit(IMSG_DATA, n->value, m.vlen);
    }
    /* then the document's top-level id list */
}
```

The framing (imsg header, TLV, or a length-prefixed buffer) is policy; hbnf
should emit against an abstract `emit(type, ptr, len)` callback so the consumer
maps it onto imsg, a socket, or a buffer without the generator being
OpenBSD-bound.

## The rebuild side

Per object type: a find helper and a `config_get*` that allocates, fills
scalars, and links into the live tree by resolving the parent id:

```c
struct node *node_find(struct config *c, objid_t id) { return c->node[id-1]; }

void config_getnode(struct config *c, const struct node_msg *m, const char *v)
{
    struct node *n = calloc(1, sizeof *n);
    n->id = m->id; n->kind = m->kind; n->value = strndup(v, m->vlen);
    if (m->parent) {                      /* parent already present (lower id) */
        struct node *p = node_find(c, m->parent);
        /* link n into p's child list — the live form */
    } else {
        /* append n->id to the document's top-level list */
    }
}
```

Reload = parse a fresh flat table, `config_set*` each object, and on the
consumer side merge new ids, update existing, purge absent (bgpd's
`merge_config`, relayd's `config_purge`/`config_setreset`).

## Relationship to the existing modes

| mode | shape | notes |
|---|---|---|
| `--backend=c` | pointer tree + inline parser | single-process |
| `--backend=c --conf` | pointer tree + `parse_config()`/global `conf` | the OpenBSD *file* shape; still pointer-linked |
| `--backend=c --idref` (proposed) | id-refs + serializer + find/rebuild | for privsep consumers |

`--conf` and `--idref` are orthogonal axes: the first is the file/entry-point
shape, the second is the cross-reference representation. A privsep consumer
wants both (`--conf --idref`).

## Open decisions

1. **Framing** — abstract `emit()` callback (recommended) vs. bind to
   imsg/`<sys/queue.h>`.
2. **id namespace** — global monotonic (relayd's `objid_t`) vs. per-type (some
   daemons keep a separate peer/prefixset space). Global is simpler; per-type
   matches bgpd.
3. **Find** — linear scan (daemon-style, simplest) vs. generated RB/hash for
   large types; could be a flag.
4. **Strings/arrays** — ids replace only the structural pointers; scalar
   `char *`/byte blobs still need length-prefixing on the wire.
5. **Table ownership** — the flat `struct config` above vs. per-type arrays;
   the serializer only needs id order.
