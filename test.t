#!/usr/bin/env lua
require 'Test.More'

package.path = "./?.lua;" .. package.path
package.cpath = "./?.so;" .. package.cpath

local cmark = require 'cmark'
local builder = require 'cmark.builder'
local tests = require 'spec-tests'

subtest("spec tests (cmark)", function()
  for _,test in ipairs(tests) do
    local doc  = cmark.parse_string(test.markdown, cmark.OPT_DEFAULT)
    local html = cmark.render_html(doc, cmark.OPT_DEFAULT + cmark.OPT_UNSAFE)
    cmark.node_free(doc)
    is(html, test.html, "example " .. tostring(test.example) ..
           " (lines " .. tostring(test.start_line) .. " - " ..
           tostring(test.end_line) .. ")")
  end
end)

local b = builder

local builds = function(node, expected, description)
  local rendered = cmark.render_html(node, cmark.OPT_DEFAULT + cmark.OPT_UNSAFE)
  cmark.node_free(node)
  return is(rendered, expected, description)
end

local returns_error = function(f, arg, expected_msg, description)
  local ok, msg = f(arg)
  -- a node passed in is still owned by the caller after an error
  if type(arg) == 'userdata' then
    cmark.node_free(arg)
  end
  is(ok, nil, description .. ' returns error status')
  is(msg, expected_msg, description .. ' error message')
end

builds(b.document { b.paragraph {"Hello ", b.emph { "world"  }, "."} },
    '<p>Hello <em>world</em>.</p>\n', "basic builder example")

builds(b.document "hi", '<p>hi</p>\n', "promotion of string to block")

builds(b.document(b.text "hi"), '<p>hi</p>\n', "promotion of inline to block")

builds(b.paragraph(77), '<p>77</p>\n', "promotion of number to inline")

builds(b.block_quote { b.paragraph "hi", b.paragraph "lo" },
    '<blockquote>\n<p>hi</p>\n<p>lo</p>\n</blockquote>\n', "blockquote")

builds(b.text("hello"), "hello", "b.text")

builds(b.link{url = "url", "hello"},
    '<a href="url">hello</a>', "b.link with string")
builds(b.link{url = "url", b.text("hello")},
    '<a href="url">hello</a>', "b.link with node")

builds(b.bullet_list { tight = true,
     b.item(b.paragraph "hi"),
     b.item(b.paragraph "lo") },
    '<ul>\n<li>hi</li>\n<li>lo</li>\n</ul>\n', "list turns table elts to items")

builds(b.bullet_list { tight = true, "hi", "lo" },
    '<ul>\n<li>hi</li>\n<li>lo</li>\n</ul>\n', "list turns table elts to items")

builds(b.ordered_list { tight = false, start = 2, delim = ')', "hi", "lo" },
    '<ol start="2">\n<li>\n<p>hi</p>\n</li>\n<li>\n<p>lo</p>\n</li>\n</ol>\n',
    "ordered list")

builds(b.bullet_list{ b.item
         { b.paragraph "one", b.paragraph "two", tight = false }},
    '<ul>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ul>\n',
    "bullet list with two paragraphs in an item")

builds(b.code_block "some code\n  ok",
  '<pre><code>some code\n  ok</code></pre>\n', "basic code block")

builds(b.code_block({info = "ruby", "some code\n  ok"}),
  '<pre><code class="language-ruby">some code\n  ok</code></pre>\n',
  "code block with info")

builds(b.html_block '<section id="foo">bar</section>',
  '<section id="foo">bar</section>\n', "html block")

builds(b.custom_block{ on_enter = "{{", on_exit = "}}", "foo\n  bar"},
  '{{\nfoo\n  bar\n}}\n', "custom block")

builds(b.thematic_break(), '<hr />\n', "thematic break")

builds(b.heading{level = 2, b.emph 'Foo', ' bar'},
  '<h2><em>Foo</em> bar</h2>\n', "heading")

local link = b.link{url = "url",
   b.text("hello"), b.text("there")}

is(#(b.get_children(link)), 2, "get_children has right length")

builds(link,
    '<a href="url">hellothere</a>', "b.link with list of nodes")

builds(b.link{url = "url", title = "tit", "hello"},
    '<a href="url" title="tit">hello</a>', "b.link with title")

builds(b.image{url = "url", title = "tit", "hello"},
    '<img src="url" alt="hello" title="tit" />', "b.image with title")

builds(b.emph "hi", '<em>hi</em>', "emph")

builds(b.strong(b.emph "hi"), '<strong><em>hi</em></strong>', "strong emph")

returns_error(b.emph, b.paragraph "text",
   "Tried to add a node with class block to a node with class inline",
   "paragraph inside emph")

returns_error(b.heading, {level = 9, "x"}, "Could not set level",
   "invalid heading level")

returns_error(b.ordered_list, {start = -1, "x"}, "Could not set start",
   "negative list start")

returns_error(b.ordered_list, {delim = "x", "x"}, "Unknown delimiter x",
   "unknown list delimiter")

returns_error(b.block_quote, b.document "x", "Could not append child",
   "document inside block quote")

returns_error(b.bullet_list, b.document "x", "Could not append child to item",
   "document wrapped in item")

returns_error(b.ordered_list, {start = -1, delim = "x", "x"}, "Unknown delimiter x",
   "fields are checked in a fixed order")

do
  -- nodes passed in are returned to the caller when a later child fails
  local para = b.paragraph "kept"
  local inner = b.document "x"
  local doc, msg = b.document{para, inner}
  is(doc, nil, "failed build after appending a passed node returns nil")
  is(msg, "Could not append child", "failed build error message")
  is(cmark.node_parent(para), nil, "passed node is detached on failure")
  is(cmark.render_html(para), "<p>kept</p>\n", "passed node is still usable")
  cmark.node_free(para)
  cmark.node_free(inner)

  -- and when building raises an error
  local text = b.text "kept"
  local status, err = pcall(b.paragraph, {text, function() error("boom", 0) end})
  is(status, false, "error while building is raised")
  is(err, "boom", "error while building is passed through")
  is(cmark.node_parent(text), nil, "passed node is detached on error")
  cmark.node_free(text)

  is(pcall(b.heading, {level = "abc", "x"}), false, "invalid field type raises an error")
end

builds(b.paragraph{"hi", b.linebreak(), "lo"}, '<p>hi<br />\nlo</p>\n',
  "linebreak")

builds(b.paragraph{"hi", b.linebreak(), "lo"}, '<p>hi<br />\nlo</p>\n',
  "linebreak, levaing off ()")

builds(b.paragraph{"hi", b.softbreak, "lo"}, '<p>hi\nlo</p>\n',
  "softbreak")

builds(b.code "some code", '<code>some code</code>', "code")

builds(b.html_inline "<a>&amp;</a>", '<a>&amp;</a>', "raw html inline")

builds(b.custom_inline{ on_enter = "{", on_exit = ".", "&" },
  '{&amp;.', "custom inline")

-- Rendered strings are malloc'd by libcmark and must be freed by the
-- wrapper after being copied into Lua. Measured via RSS, so Linux only.
local function rss_kb()
  local f = io.open("/proc/self/status")
  if not f then return nil end
  local status = f:read("*a")
  f:close()
  return tonumber(status:match("VmRSS:%s+(%d+)"))
end

subtest("rendered strings are freed", function()
  -- sanitizer builds hold freed memory in quarantine; LeakSanitizer covers this
  if os.getenv("SKIP_RSS_TEST") or not rss_kb() then
    skip("RSS measurement unavailable", 6)
    return
  end
  local md = ("# Title\n\nSome *text* with [a link](http://x.com).\n\n"):rep(100)
  local renderers = {
    markdown_to_html = function() return cmark.markdown_to_html(md, #md, cmark.OPT_DEFAULT) end,
    render_html = function(doc) return cmark.render_html(doc, cmark.OPT_DEFAULT) end,
    render_xml = function(doc) return cmark.render_xml(doc, cmark.OPT_DEFAULT) end,
    render_man = function(doc) return cmark.render_man(doc, cmark.OPT_DEFAULT, 0) end,
    render_commonmark = function(doc) return cmark.render_commonmark(doc, cmark.OPT_DEFAULT, 0) end,
    render_latex = function(doc) return cmark.render_latex(doc, cmark.OPT_DEFAULT, 0) end,
  }
  local doc = cmark.parse_string(md, cmark.OPT_DEFAULT)
  for name, render in pairs(renderers) do
    local iterations = 2000
    render(doc)
    collectgarbage()
    local before = rss_kb()
    for _ = 1, iterations do render(doc) end
    collectgarbage()
    local growth = rss_kb() - before
    -- each output is several KB, so a leak would grow by well over 5MB
    ok(growth < 5000, name .. " does not leak (grew " .. growth .. " KB)")
  end
  cmark.node_free(doc)
end)

subtest("binding", function()
  local doc = cmark.parse_string("# hi\n\n- a\n")
  local heading = cmark.node_first_child(doc)

  ok(cmark.node_parent(heading) == doc, "nodes for the same pointer are equal")
  ok(cmark.node_next(heading) ~= doc, "different nodes are not equal")
  is(cmark.node_parent(doc), nil, "NULL node returns nil")
  is(cmark.node_get_literal(heading), nil, "NULL string returns nil")

  is(cmark.node_set_heading_level(heading, 2), 1, "setter returns 1 on success")
  is(cmark.node_set_heading_level(heading, 9), 0, "setter returns 0 on failure")
  is(cmark.node_get_heading_level(heading), 2, "failed setter leaves value")

  is(cmark.node_is_block(heading), true, "node_is_block")
  is(cmark.node_is_inline(heading), false, "node_is_inline")
  local hr = cmark.node_new(cmark.NODE_THEMATIC_BREAK)
  is(cmark.node_is_leaf(hr), true, "node_is_leaf")
  cmark.node_free(hr)

  is(cmark.markdown_to_html("hi", 1000, cmark.OPT_DEFAULT), "<p>hi</p>\n",
     "length longer than the string is clamped")
  is(cmark.markdown_to_html("hi there", 2, cmark.OPT_DEFAULT), "<p>hi</p>\n",
     "shorter length is respected")

  local raw = cmark.parse_string("<b>x</b>")
  is(cmark.render_html(raw),
     "<p><!-- raw HTML omitted -->x<!-- raw HTML omitted --></p>\n",
     "options default to OPT_DEFAULT")
  cmark.node_free(raw)

  ok(doc ~= io.stdout, "node compared with other userdata is not equal")

  local other = cmark.parse_string("other")
  local errors = {
    {"node_next(nil)", function() return cmark.node_next(nil) end},
    {"node_free(nil)", function() return cmark.node_free(nil) end},
    {"node_get_type(string)", function() return cmark.node_get_type("x") end},
    {"node_new(invalid type)", function() return cmark.node_new(99) end},
    {"node_new(NaN)", function() return cmark.node_new(0/0) end},
    {"out of range int", function() return cmark.node_set_list_start(heading, 1e12) end},
    {"negative length", function() return cmark.markdown_to_html("x", -1) end},
    {"NaN length", function() return cmark.markdown_to_html("x", 0/0) end},
    {"iter_reset outside root", function()
      return cmark.iter_reset(cmark.iter_new(doc), other, cmark.EVENT_ENTER)
    end},
    {"iter_reset invalid event", function()
      return cmark.iter_reset(cmark.iter_new(doc), heading, cmark.EVENT_DONE)
    end},
  }
  for _, e in ipairs(errors) do
    is(pcall(e[2]), false, e[1] .. " raises an error")
  end

  local freed = cmark.parse_string("x")
  cmark.node_free(freed)
  local status, err = pcall(cmark.render_html, freed)
  is(status, false, "using a freed node raises an error")
  like(err, "freed cmark_node", "freed node error message")
  is(pcall(function() return freed == other end), false,
     "comparing a freed node raises an error")
  cmark.node_free(other)

  local reset_iter = cmark.iter_new(doc)
  cmark.iter_reset(reset_iter, heading, cmark.EVENT_EXIT)
  is(cmark.iter_get_node(reset_iter) == heading, true, "iter_reset within root")
  is(cmark.iter_next(reset_iter), cmark.EVENT_ENTER, "iter_reset continues")
  cmark.iter_free(reset_iter)

  local iter = cmark.iter_new(doc)
  cmark.iter_free(iter)
  is(pcall(cmark.iter_next, iter), false, "using a freed iterator raises an error")
  cmark.iter_free(iter)
  pass("freeing an iterator twice is a no-op")

  -- not freed explicitly: collected iterators and parsers free themselves,
  -- which the sanitizer job checks
  for _ in cmark.walk(doc) do break end
  cmark.iter_new(doc)
  cmark.parser_new()
  collectgarbage()
  collectgarbage()

  local types = {}
  for _, entering, node_type in cmark.walk(doc) do
    if entering then types[#types + 1] = node_type end
  end
  is_deeply(types, {cmark.NODE_DOCUMENT, cmark.NODE_HEADING, cmark.NODE_TEXT,
    cmark.NODE_LIST, cmark.NODE_ITEM, cmark.NODE_PARAGRAPH, cmark.NODE_TEXT},
    "walk visits nodes in order")

  local parser = cmark.parser_new(cmark.OPT_DEFAULT)
  cmark.parser_feed(parser, "*a")
  cmark.parser_feed(parser, "b*", 2)
  local streamed = cmark.parser_finish(parser)
  cmark.parser_free(parser)
  is(cmark.render_html(streamed), "<p><em>ab</em></p>\n", "streaming parser")
  cmark.node_free(streamed)

  parser = cmark.parser_new()
  local finished = cmark.parser_finish(parser)
  is(pcall(cmark.parser_finish, parser), false, "finishing twice raises an error")
  is(pcall(cmark.parser_feed, parser, "x"), false, "feeding after finish raises an error")
  cmark.node_free(finished)

  cmark.node_free(doc)
end)

done_testing()
