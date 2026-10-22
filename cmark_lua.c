/*
 * Lua bindings for libcmark.
 *
 * Functions and constants are exposed with the cmark_/CMARK_ prefix removed,
 * e.g. cmark_parse_document -> cmark.parse_document and
 * CMARK_NODE_PARAGRAPH -> cmark.NODE_PARAGRAPH.
 *
 * Nodes are not garbage collected: the caller frees a tree by calling
 * node_free on its root. Iterators and parsers are freed when collected if
 * not freed explicitly.
 */

#include <limits.h>
#include <stddef.h>

#include "lua.h"
#include "lauxlib.h"

#include "cmark.h"

int luaopen_cmark(lua_State *L);

/* Exported for C code that wants to push nodes for use with this module */
void push_cmark_node(lua_State *L, cmark_node *node);

#define NODE_MT "cmark_node"
#define ITER_MT "cmark_iter"
#define PARSER_MT "cmark_parser"

#if LUA_VERSION_NUM < 502
#define luaL_setfuncs(L, l, nup) luaL_register(L, NULL, l)
#endif

/* Casting a NaN or out of range number to int is undefined, so reject them */
static int number_to_int(lua_State *L, int arg, lua_Number n) {
  luaL_argcheck(L, n >= INT_MIN && n <= INT_MAX, arg, "number out of range");
  return (int)n;
}

static int check_int(lua_State *L, int arg) {
  return number_to_int(L, arg, luaL_checknumber(L, arg));
}

static int opt_int(lua_State *L, int arg, int def) {
  return number_to_int(L, arg, luaL_optnumber(L, arg, def));
}

/* Length arguments are clamped to the string's actual length so that a bad
 * length can never read past the end of the string. */
static size_t check_len(lua_State *L, int arg, size_t max) {
  lua_Number n = luaL_checknumber(L, arg);
  luaL_argcheck(L, n >= 0, arg, "length must not be negative");
  return n > (lua_Number)max ? max : (size_t)n;
}

static void push_result_string(lua_State *L, char *s) {
  lua_pushstring(L, s);
  cmark_get_default_mem_allocator()->free(s);
}

/* Nodes */

static void node_metatable(lua_State *L);

static cmark_node **new_node_ud(lua_State *L) {
  cmark_node **ud = (cmark_node **)lua_newuserdata(L, sizeof(cmark_node *));
  *ud = NULL;
  node_metatable(L);
  lua_setmetatable(L, -2);
  return ud;
}

void push_cmark_node(lua_State *L, cmark_node *node) {
  if (node == NULL) {
    lua_pushnil(L);
    return;
  }
  *new_node_ud(L) = node;
}

static cmark_node **check_node_ud(lua_State *L, int arg) {
  cmark_node **ud = (cmark_node **)luaL_checkudata(L, arg, NODE_MT);
  if (*ud == NULL) {
    luaL_argerror(L, arg, "attempt to use a freed cmark_node");
  }
  return ud;
}

static cmark_node *check_node(lua_State *L, int arg) {
  return *check_node_ud(L, arg);
}

/* Returns the node userdata at index, or NULL if the value is not a node */
static cmark_node **test_node_ud(lua_State *L, int index) {
  cmark_node **ud = (cmark_node **)lua_touserdata(L, index);
  int matches;
  if (ud == NULL || !lua_getmetatable(L, index)) {
    return NULL;
  }
  luaL_getmetatable(L, NODE_MT);
  matches = lua_rawequal(L, -1, -2);
  lua_pop(L, 2);
  return matches ? ud : NULL;
}

/* On Lua 5.3+ __eq is also called when comparing a node with another kind of
 * userdata, which is never equal */
static int node_eq(lua_State *L) {
  cmark_node **a = test_node_ud(L, 1);
  cmark_node **b = test_node_ud(L, 2);
  if (a == NULL || b == NULL) {
    lua_pushboolean(L, 0);
    return 1;
  }
  lua_pushboolean(L, *check_node_ud(L, 1) == *check_node_ud(L, 2));
  return 1;
}

static int node_tostring(lua_State *L) {
  cmark_node **ud = (cmark_node **)luaL_checkudata(L, 1, NODE_MT);
  if (*ud == NULL) {
    lua_pushstring(L, "cmark_node (freed)");
  } else {
    lua_pushfstring(L, "cmark_node (%s): %p", cmark_node_get_type_string(*ud),
                    (void *)*ud);
  }
  return 1;
}

static void node_metatable(lua_State *L) {
  if (luaL_newmetatable(L, NODE_MT)) {
    lua_pushcfunction(L, node_eq);
    lua_setfield(L, -2, "__eq");
    lua_pushcfunction(L, node_tostring);
    lua_setfield(L, -2, "__tostring");
  }
}

static int valid_node_type(int type) {
  return (type >= CMARK_NODE_FIRST_BLOCK && type <= CMARK_NODE_LAST_BLOCK) ||
         (type >= CMARK_NODE_FIRST_INLINE && type <= CMARK_NODE_LAST_INLINE);
}

static int l_node_new(lua_State *L) {
  int type = check_int(L, 1);
  luaL_argcheck(L, valid_node_type(type), 1, "invalid node type");
  push_cmark_node(L, cmark_node_new((cmark_node_type)type));
  return 1;
}

/* Clears the userdata passed in, so further use of that value raises an
 * error. Other references to the node or its descendants are not tracked. */
static int l_node_free(lua_State *L) {
  cmark_node **ud = check_node_ud(L, 1);
  cmark_node_free(*ud);
  *ud = NULL;
  return 0;
}

#define NODE_TO_NODE(name)                                                     \
  static int l_##name(lua_State *L) {                                          \
    push_cmark_node(L, cmark_##name(check_node(L, 1)));                        \
    return 1;                                                                  \
  }

#define NODE_TO_INT(name)                                                      \
  static int l_##name(lua_State *L) {                                          \
    lua_pushinteger(L, (lua_Integer)cmark_##name(check_node(L, 1)));           \
    return 1;                                                                  \
  }

#define NODE_TO_BOOL(name)                                                     \
  static int l_##name(lua_State *L) {                                          \
    lua_pushboolean(L, cmark_##name(check_node(L, 1)));                        \
    return 1;                                                                  \
  }

#define NODE_TO_STRING(name)                                                   \
  static int l_##name(lua_State *L) {                                          \
    lua_pushstring(L, cmark_##name(check_node(L, 1)));                         \
    return 1;                                                                  \
  }

/* Setters return 1 on success and 0 on failure, like the C API */
#define SET_STRING(name)                                                       \
  static int l_##name(lua_State *L) {                                          \
    cmark_node *node = check_node(L, 1);                                       \
    lua_pushinteger(L, cmark_##name(node, luaL_optstring(L, 2, NULL)));        \
    return 1;                                                                  \
  }

#define SET_INT(name, type)                                                    \
  static int l_##name(lua_State *L) {                                          \
    cmark_node *node = check_node(L, 1);                                       \
    lua_pushinteger(L, cmark_##name(node, (type)check_int(L, 2)));             \
    return 1;                                                                  \
  }

#define NODE_NODE_TO_INT(name)                                                 \
  static int l_##name(lua_State *L) {                                          \
    cmark_node *node = check_node(L, 1);                                       \
    lua_pushinteger(L, cmark_##name(node, check_node(L, 2)));                  \
    return 1;                                                                  \
  }

#define NODE_TO_VOID(name)                                                     \
  static int l_##name(lua_State *L) {                                          \
    cmark_##name(check_node(L, 1));                                            \
    return 0;                                                                  \
  }

NODE_TO_NODE(node_next)
NODE_TO_NODE(node_previous)
NODE_TO_NODE(node_parent)
NODE_TO_NODE(node_first_child)
NODE_TO_NODE(node_last_child)

NODE_TO_BOOL(node_is_block)
NODE_TO_BOOL(node_is_inline)
NODE_TO_BOOL(node_is_leaf)

NODE_TO_INT(node_get_type)
NODE_TO_INT(node_get_heading_level)
NODE_TO_INT(node_get_list_type)
NODE_TO_INT(node_get_list_delim)
NODE_TO_INT(node_get_list_start)
NODE_TO_INT(node_get_list_tight)
NODE_TO_INT(node_get_start_line)
NODE_TO_INT(node_get_start_column)
NODE_TO_INT(node_get_end_line)
NODE_TO_INT(node_get_end_column)

NODE_TO_STRING(node_get_type_string)
NODE_TO_STRING(node_get_literal)
NODE_TO_STRING(node_get_fence_info)
NODE_TO_STRING(node_get_url)
NODE_TO_STRING(node_get_title)
NODE_TO_STRING(node_get_on_enter)
NODE_TO_STRING(node_get_on_exit)

SET_STRING(node_set_literal)
SET_STRING(node_set_fence_info)
SET_STRING(node_set_url)
SET_STRING(node_set_title)
SET_STRING(node_set_on_enter)
SET_STRING(node_set_on_exit)

SET_INT(node_set_heading_level, int)
SET_INT(node_set_list_type, cmark_list_type)
SET_INT(node_set_list_delim, cmark_delim_type)
SET_INT(node_set_list_start, int)
SET_INT(node_set_list_tight, int)

NODE_NODE_TO_INT(node_insert_before)
NODE_NODE_TO_INT(node_insert_after)
NODE_NODE_TO_INT(node_replace)
NODE_NODE_TO_INT(node_prepend_child)
NODE_NODE_TO_INT(node_append_child)

NODE_TO_VOID(node_unlink)
NODE_TO_VOID(consolidate_text_nodes)

/* Iterators */

static cmark_iter **check_iter_ud(lua_State *L, int arg) {
  return (cmark_iter **)luaL_checkudata(L, arg, ITER_MT);
}

static cmark_iter *check_iter(lua_State *L, int arg) {
  cmark_iter **ud = check_iter_ud(L, arg);
  if (*ud == NULL) {
    luaL_argerror(L, arg, "attempt to use a freed cmark_iter");
  }
  return *ud;
}

static int iter_gc(lua_State *L) {
  cmark_iter **ud = check_iter_ud(L, 1);
  if (*ud != NULL) {
    cmark_iter_free(*ud);
    *ud = NULL;
  }
  return 0;
}

static int l_iter_new(lua_State *L) {
  cmark_node *root = check_node(L, 1);
  cmark_iter **ud = (cmark_iter **)lua_newuserdata(L, sizeof(cmark_iter *));
  *ud = NULL;
  luaL_getmetatable(L, ITER_MT);
  lua_setmetatable(L, -2);
  *ud = cmark_iter_new(root);
  return 1;
}

static int l_iter_next(lua_State *L) {
  lua_pushinteger(L, cmark_iter_next(check_iter(L, 1)));
  return 1;
}

static int l_iter_get_node(lua_State *L) {
  push_cmark_node(L, cmark_iter_get_node(check_iter(L, 1)));
  return 1;
}

static int l_iter_get_event_type(lua_State *L) {
  lua_pushinteger(L, cmark_iter_get_event_type(check_iter(L, 1)));
  return 1;
}

static int l_iter_get_root(lua_State *L) {
  push_cmark_node(L, cmark_iter_get_root(check_iter(L, 1)));
  return 1;
}

/* cmark_iter_next asserts if the current node is outside the iterator's
 * root, so the node and event are validated here */
static int l_iter_reset(lua_State *L) {
  cmark_iter *iter = check_iter(L, 1);
  cmark_node *current = check_node(L, 2);
  int event_type = check_int(L, 3);
  cmark_node *root = cmark_iter_get_root(iter);
  cmark_node *cur = current;

  while (cur != NULL && cur != root) {
    cur = cmark_node_parent(cur);
  }
  luaL_argcheck(L, cur != NULL, 2, "node is not within the iterator's root");
  luaL_argcheck(L,
                event_type == CMARK_EVENT_ENTER ||
                    event_type == CMARK_EVENT_EXIT,
                3, "event type must be EVENT_ENTER or EVENT_EXIT");
  cmark_iter_reset(iter, current, (cmark_event_type)event_type);
  return 0;
}

static int walk_next(lua_State *L) {
  cmark_iter **ud = (cmark_iter **)lua_touserdata(L, lua_upvalueindex(1));
  cmark_node *node;
  cmark_event_type ev;

  if (*ud == NULL) {
    return 0;
  }
  ev = cmark_iter_next(*ud);
  if (ev == CMARK_EVENT_DONE || ev == CMARK_EVENT_NONE) {
    cmark_iter_free(*ud);
    *ud = NULL;
    return 0;
  }
  node = cmark_iter_get_node(*ud);
  push_cmark_node(L, node);
  lua_pushboolean(L, ev == CMARK_EVENT_ENTER);
  lua_pushinteger(L, cmark_node_get_type(node));
  return 3;
}

/* for node, entering, node_type in cmark.walk(root) do ... end
 * The iterator is freed when the walk finishes, or when it is collected if
 * the loop exits early. */
static int l_walk(lua_State *L) {
  l_iter_new(L);
  lua_pushcclosure(L, walk_next, 1);
  return 1;
}

/* Parsing */

/* The parser owns its document until parser_finish returns it, but
 * cmark_parser_free does not free it, so an unfinished parser is finished
 * before being freed to release the document. */
typedef struct {
  cmark_parser *parser;
  int finished;
} parser_box;

static parser_box *check_parser_box(lua_State *L, int arg) {
  return (parser_box *)luaL_checkudata(L, arg, PARSER_MT);
}

static parser_box *check_open_parser(lua_State *L, int arg) {
  parser_box *box = check_parser_box(L, arg);
  if (box->parser == NULL) {
    luaL_argerror(L, arg, "attempt to use a freed cmark_parser");
  }
  if (box->finished) {
    luaL_argerror(L, arg, "parser has already finished");
  }
  return box;
}

static int parser_gc(lua_State *L) {
  parser_box *box = check_parser_box(L, 1);
  if (box->parser != NULL) {
    if (!box->finished) {
      cmark_node_free(cmark_parser_finish(box->parser));
    }
    cmark_parser_free(box->parser);
    box->parser = NULL;
  }
  return 0;
}

static int l_parser_new(lua_State *L) {
  int options = opt_int(L, 1, CMARK_OPT_DEFAULT);
  parser_box *box = (parser_box *)lua_newuserdata(L, sizeof(parser_box));
  box->parser = NULL;
  box->finished = 0;
  luaL_getmetatable(L, PARSER_MT);
  lua_setmetatable(L, -2);
  box->parser = cmark_parser_new(options);
  return 1;
}

static int l_parser_feed(lua_State *L) {
  parser_box *box = check_open_parser(L, 1);
  size_t len;
  const char *buffer = luaL_checklstring(L, 2, &len);
  if (!lua_isnoneornil(L, 3)) {
    len = check_len(L, 3, len);
  }
  cmark_parser_feed(box->parser, buffer, len);
  return 0;
}

static int l_parser_finish(lua_State *L) {
  parser_box *box = check_open_parser(L, 1);
  /* allocated first so a memory error can't leave the document unowned */
  cmark_node **ud = new_node_ud(L);
  *ud = cmark_parser_finish(box->parser);
  box->finished = 1;
  return 1;
}

static int l_parse_document(lua_State *L) {
  size_t len;
  const char *buffer = luaL_checklstring(L, 1, &len);
  len = check_len(L, 2, len);
  push_cmark_node(
      L, cmark_parse_document(buffer, len, opt_int(L, 3, CMARK_OPT_DEFAULT)));
  return 1;
}

static int l_parse_string(lua_State *L) {
  size_t len;
  const char *buffer = luaL_checklstring(L, 1, &len);
  push_cmark_node(
      L, cmark_parse_document(buffer, len, opt_int(L, 2, CMARK_OPT_DEFAULT)));
  return 1;
}

static int l_markdown_to_html(lua_State *L) {
  size_t len;
  const char *text = luaL_checklstring(L, 1, &len);
  len = check_len(L, 2, len);
  push_result_string(
      L, cmark_markdown_to_html(text, len, opt_int(L, 3, CMARK_OPT_DEFAULT)));
  return 1;
}

/* Rendering */

static int l_render_xml(lua_State *L) {
  cmark_node *root = check_node(L, 1);
  push_result_string(L,
                     cmark_render_xml(root, opt_int(L, 2, CMARK_OPT_DEFAULT)));
  return 1;
}

static int l_render_html(lua_State *L) {
  cmark_node *root = check_node(L, 1);
  push_result_string(L,
                     cmark_render_html(root, opt_int(L, 2, CMARK_OPT_DEFAULT)));
  return 1;
}

#define RENDER_WITH_WIDTH(name)                                                \
  static int l_##name(lua_State *L) {                                          \
    cmark_node *root = check_node(L, 1);                                       \
    int options = opt_int(L, 2, CMARK_OPT_DEFAULT);                            \
    push_result_string(L, cmark_##name(root, options, opt_int(L, 3, 0)));      \
    return 1;                                                                  \
  }

RENDER_WITH_WIDTH(render_man)
RENDER_WITH_WIDTH(render_latex)

static int is_detached_item(cmark_node *node) {
  return node != NULL && cmark_node_get_type(node) == CMARK_NODE_ITEM &&
         cmark_node_parent(node) == NULL;
}

/* The commonmark renderer reads the list containing an item when entering
 * each of the item's children, without checking that there is one, which
 * crashes when rendering an item that is not in a list and has children, or a
 * child of one */
static int l_render_commonmark(lua_State *L) {
  cmark_node *root = check_node(L, 1);
  int options = opt_int(L, 2, CMARK_OPT_DEFAULT);
  luaL_argcheck(L,
                !(is_detached_item(root) && cmark_node_first_child(root)) &&
                    !is_detached_item(cmark_node_parent(root)),
                1, "cannot render a list item that is not in a list");
  push_result_string(L,
                     cmark_render_commonmark(root, options, opt_int(L, 3, 0)));
  return 1;
}

static int l_version(lua_State *L) {
  lua_pushinteger(L, cmark_version());
  return 1;
}

static int l_version_string(lua_State *L) {
  lua_pushstring(L, cmark_version_string());
  return 1;
}

#define FN(name) {#name, l_##name}

static const luaL_Reg functions[] = {
    FN(markdown_to_html),
    FN(node_new),
    FN(node_free),
    FN(node_next),
    FN(node_previous),
    FN(node_parent),
    FN(node_first_child),
    FN(node_last_child),
    FN(node_is_block),
    FN(node_is_inline),
    FN(node_is_leaf),
    FN(iter_new),
    {"iter_free", iter_gc},
    FN(iter_next),
    FN(iter_get_node),
    FN(iter_get_event_type),
    FN(iter_get_root),
    FN(iter_reset),
    FN(node_get_type),
    FN(node_get_type_string),
    FN(node_get_literal),
    FN(node_set_literal),
    FN(node_get_heading_level),
    FN(node_set_heading_level),
    FN(node_get_list_type),
    FN(node_set_list_type),
    FN(node_get_list_delim),
    FN(node_set_list_delim),
    FN(node_get_list_start),
    FN(node_set_list_start),
    FN(node_get_list_tight),
    FN(node_set_list_tight),
    FN(node_get_fence_info),
    FN(node_set_fence_info),
    FN(node_get_url),
    FN(node_set_url),
    FN(node_get_title),
    FN(node_set_title),
    FN(node_get_on_enter),
    FN(node_set_on_enter),
    FN(node_get_on_exit),
    FN(node_set_on_exit),
    FN(node_get_start_line),
    FN(node_get_start_column),
    FN(node_get_end_line),
    FN(node_get_end_column),
    FN(node_unlink),
    FN(node_insert_before),
    FN(node_insert_after),
    FN(node_replace),
    FN(node_prepend_child),
    FN(node_append_child),
    FN(consolidate_text_nodes),
    FN(parser_new),
    {"parser_free", parser_gc},
    FN(parser_feed),
    FN(parser_finish),
    FN(parse_document),
    FN(parse_string),
    FN(walk),
    FN(render_xml),
    FN(render_html),
    FN(render_man),
    FN(render_commonmark),
    FN(render_latex),
    FN(version),
    FN(version_string),
    {NULL, NULL}};

#define CONST(name) {#name, CMARK_##name}

static const struct {
  const char *name;
  int value;
} constants[] = {
    CONST(NODE_NONE),
    CONST(NODE_DOCUMENT),
    CONST(NODE_BLOCK_QUOTE),
    CONST(NODE_LIST),
    CONST(NODE_ITEM),
    CONST(NODE_CODE_BLOCK),
    CONST(NODE_HTML_BLOCK),
    CONST(NODE_CUSTOM_BLOCK),
    CONST(NODE_PARAGRAPH),
    CONST(NODE_HEADING),
    CONST(NODE_THEMATIC_BREAK),
    CONST(NODE_FIRST_BLOCK),
    CONST(NODE_LAST_BLOCK),
    CONST(NODE_TEXT),
    CONST(NODE_SOFTBREAK),
    CONST(NODE_LINEBREAK),
    CONST(NODE_CODE),
    CONST(NODE_HTML_INLINE),
    CONST(NODE_CUSTOM_INLINE),
    CONST(NODE_EMPH),
    CONST(NODE_STRONG),
    CONST(NODE_LINK),
    CONST(NODE_IMAGE),
    CONST(NODE_FIRST_INLINE),
    CONST(NODE_LAST_INLINE),
    CONST(NO_LIST),
    CONST(BULLET_LIST),
    CONST(ORDERED_LIST),
    CONST(NO_DELIM),
    CONST(PERIOD_DELIM),
    CONST(PAREN_DELIM),
    CONST(EVENT_NONE),
    CONST(EVENT_DONE),
    CONST(EVENT_ENTER),
    CONST(EVENT_EXIT),
    CONST(OPT_DEFAULT),
    CONST(OPT_SOURCEPOS),
    CONST(OPT_HARDBREAKS),
    CONST(OPT_SAFE),
    CONST(OPT_UNSAFE),
    CONST(OPT_NOBREAKS),
    CONST(OPT_NORMALIZE),
    CONST(OPT_VALIDATE_UTF8),
    CONST(OPT_SMART),
    {NULL, 0}};

int luaopen_cmark(lua_State *L) {
  int i;

  node_metatable(L);
  lua_pop(L, 1);

  luaL_newmetatable(L, ITER_MT);
  lua_pushcfunction(L, iter_gc);
  lua_setfield(L, -2, "__gc");
  lua_pop(L, 1);

  luaL_newmetatable(L, PARSER_MT);
  lua_pushcfunction(L, parser_gc);
  lua_setfield(L, -2, "__gc");
  lua_pop(L, 1);

  lua_newtable(L);
  luaL_setfuncs(L, functions, 0);
  for (i = 0; constants[i].name != NULL; i++) {
    lua_pushinteger(L, constants[i].value);
    lua_setfield(L, -2, constants[i].name);
  }
  return 1;
}
