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
  cmark.node_free(arg)
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


done_testing()
