%module cmark
%{
#include "cmark.h"
%}

// Renames:
// CMARK_NODE_PARAGRAPH -> NODE_PARAGRAPH
// cmark_parse_document -> parse_document
%rename("%(regex:/^(cmark|CMARK)_(.*)/\\2/)s") "";

// These return malloc'd buffers owned by the caller. The string is copied
// into Lua, so the buffer must be freed after it is pushed.
%typemap(newfree) char * "free($1);";
%newobject cmark_markdown_to_html;
%newobject cmark_render_xml;
%newobject cmark_render_html;
%newobject cmark_render_man;
%newobject cmark_render_commonmark;
%newobject cmark_render_latex;

%include "cmark.h"

%{
extern void push_cmark_node(lua_State *L, cmark_node *node)
{
        SWIG_NewPointerObj(L,node,SWIGTYPE_p_cmark_node,0);
}
%}

%luacode {

function cmark.parse_string(s, opts)
   return cmark.parse_document(s, string.len(s), opts)
end

function cmark.walk(node)
   local iter = cmark.iter_new(node)
   return function()
     while true do
         local et = cmark.iter_next(iter)
         if et == cmark.EVENT_DONE then break end
         local cur = cmark.iter_get_node(iter)
         return cur, (et == cmark.EVENT_ENTER), cmark.node_get_type(cur)
     end
     cmark.iter_free(iter)
     return nil
   end
end

}
