cmark-lua
=========

Lua wrapper for [libcmark](https://github.com/commonmark/cmark),
CommonMark parsing and rendering library

This is a maintained fork of [jgm/cmark-lua](https://github.com/jgm/cmark-lua),
published to LuaRocks under the `leafo` namespace. The module is still
loaded with `require("cmark")`.

To install:  `luarocks install leafo/cmark` (requires LuaRocks 3.0+).

Always install with the `leafo/` prefix. An unprefixed
`luarocks install cmark`, or another rock depending on `cmark`,
resolves to the original rock.

Rock versions are the upstream cmark version followed by a release
number for these bindings, e.g. `0.31.2.1`. The exact upstream commit
the C sources were taken from is recorded in `ext/UPSTREAM`.

cmark
-----

`cmark` exposes the libcmark API, as documented in the `cmark(3)`
man page.  Basic usage:

``` lua
local cmark = require("cmark")

local doc = cmark.parse_string(input, cmark.OPT_DEFAULT)
local html = cmark.render_html(doc, cmark.OPT_DEFAULT)
cmark.node_free(doc)
```

For convenience, constants and functions are renamed so that
an initial `cmark_` or `CMARK_` is omitted:  for example,
`CMARK_NODE_PARAGRAPH` is exposed as `cmark.NODE_PARAGRAPH` and
`cmark_parse_document` as `cmark.parse_document`.

`options` arguments default to `cmark.OPT_DEFAULT` and `width`
arguments default to `0` when omitted. Length arguments, as in
`parse_document(s, len, options)`, are clamped to the length of the
string.

Two additional functions are provided:

`cmark.parse_string(s, opts)` is like `parse_document`, but
does not require you to specify the length of the input
string.

`cmark.walk(node)` wraps `cmark`'s iterator interface in a
format that is more lua-esque.  Usage example:

``` lua
local links = 0
for cur, entering, node_type in cmark.walk(doc) do
   if node_type == cmark.NODE_LINK and not entering then
       links = links + 1
       -- insert " (link #n)" after the link:
       local t = cmark.node_new(cmark.NODE_TEXT)
       cmark.node_set_literal(t, string.format(" (link #%d)", links))
       cmark.node_insert_after(cur, t)
   end
end
```

### Memory

Nodes are not garbage collected. The memory allocated by libcmark
for a document must be freed by calling `cmark.node_free` on the
document node, which frees all of its children as well. A node
value that has been passed to `node_free` raises an error if it is
used again, but other references to the freed nodes (such as
children obtained earlier) are not tracked and must not be used.

Iterators and parsers are freed automatically when garbage
collected, or explicitly with `iter_free` and `parser_free`. A
parser that is freed without calling `parser_finish` also frees the
document it was building.

An iterator (including the one used by `walk`) refers to the tree
it was created for, so the tree must not be freed while the
iterator is still in use. As with libcmark, modifying the tree
while iterating is only safe for a node after its exit event (or
its enter event, for leaf nodes): unlinking or freeing a node that
the iterator has not yet finished with can crash the process.

Nodes compare equal with `==` when they refer to the same node.

Passing `nil` or a value of the wrong type where a node, iterator or
parser is expected raises an error.

In addition, a C function

``` C
void push_cmark_node(lua_State *L, cmark_node *node)
```

is exported to make it easier to use these functions
from the C API.

### Differences from jgm/cmark-lua

The bindings were originally generated with SWIG and are now
written by hand. They are compatible with the SWIG bindings except:

- Strings returned by `markdown_to_html` and the `render_*`
  functions are freed (the SWIG bindings leaked them).
- Lengths larger than the string are clamped, instead of reading
  past the end of the string. A negative length raises an error.
- `nil` where a node is expected raises an error instead of
  crashing. `node_new` rejects invalid node types.
- `parser_finish` can only be called once per parser, and
  `parser_feed` raises an error after it.
- Nodes are comparable with `==`. Integers are returned as integers
  on Lua 5.3+ (SWIG returned floats).
- The module no longer sets a global `cmark` variable.
- Extra arguments are ignored instead of raising an error.
- `node_is_block`, `node_is_inline` and `node_is_leaf` are
  available.
- Functions that can't be meaningfully called from Lua are not
  exposed: `get_default_mem_allocator`, `node_new_with_mem`,
  `parser_new_with_mem`, `parser_new_with_mem_into_root`,
  `parse_file`, `node_get_user_data` and `node_set_user_data`.

For a higher-level interface, see
[lcmark](https://github.com/jgm/lcmark).

cmark.builder
-------------

A special module, `cmark.builder`, is provided to make it easier
to construct cmark nodes.

Usage examples:

```lua
local b = require 'cmark.builder'
local mydoc = b.document{
                b.paragraph{
                  b.text "Hello ",
                  b.emph{
                    b.text "world" },
                  b.link{
                    url = "http://example.com",
                    b.text "!" } } }
```

The arguments to builder functions are generally
tables.  Key-value pairs are used to set attributes,
and the other values are used as children or literal
string content, as appropriate.

The library will interpret values as the appropriate
types, when possible.  So, you can supply a single
value instead of an array.  And you can supply a string
instead of an inline node, or a node instead of a list
item.  The following is equivalent to the example above:

```lua
local mydoc = b.document{
                b.paragraph{
                  "Hello ", b.emph "world",
                  b.link{ url="http://example.com", "!"} }}
```

If a node can't be built, for example because an attribute is
invalid or a child can't be placed in the node, the builder
returns `nil` and an error message. Nodes passed in as children
are still owned by the caller in that case, and are detached from
the partially built node before it is freed. Because a nested
builder call that fails returns `nil`, which ends the list of
children, check each nested result if you need to detect errors.

The builder functions are

```lua
builder.document{block1, block2, ...}
builder.block_quote{block1, block2, ...}
builder.ordered_list{delim = cmark.PAREN_DELIM, item1, item2, ...}
-- attributes: delim, start, tight
builder.bullet_list  -- attributes: tight
builder.item
builder.code_block  -- attributes: info
builder.html_block
builder.custom_block --  attributes: on_enter, on_exit
builder.thematic_break
builder.heading  -- attributes: level
builder.paragraph
builder.text
builder.emph
builder.strong
builder.link   -- attributes: title, url
builder.image  -- attributes: title, url
builder.linebreak
builder.softbreak
builder.code
builder.html_inline
builder.custom_inline  -- attributes: on_enter, on_exit
builder.get_children(node) -- returns children of a node as a table
```

For developers
--------------

`make` builds the rock and installs it locally.

`make test` runs some tests.  These are in `test.t`.
You'll need the `prove` executable and the `lua-TestMore` rock.

`make update` will update the C sources and spec test from the
`../cmark` directory (override with `CMARK_DIR=...`), and record
the upstream commit in `ext/UPSTREAM`. `../cmark` must be built
with CMake as a shared library (`-DBUILD_SHARED_LIBS=ON`), since
`cmark_export.h` and `cmark_version.h` are copied from its build
directory.

To release, bump `VERSION` in the `Makefile`, tag the commit with
that version prefixed with `v` (e.g. `v0.31.2.1`) and push the tag,
then run `make upload` (which uses `moonrocks`).

