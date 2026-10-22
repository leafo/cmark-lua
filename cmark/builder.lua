local c = require('cmark')

local builder = {}

-- returns 'inline', 'block', 'item', or 'unknown'
local node_get_class = function(node)
  local nt = c.node_get_type(node)
  if nt == c.NODE_ITEM then
    return 'item'
  elseif (nt >= c.NODE_FIRST_BLOCK and nt <= c.NODE_LAST_BLOCK) then
    return 'block'
  elseif (nt >= c.NODE_FIRST_INLINE and nt <= c.NODE_LAST_INLINE) then
    return 'inline'
  end
  return 'unknown'
end

local add_children
-- 'builder.add_children(node, {node1, node2})'
-- adds 'node1' and 'node2' as children of 'node'.
-- 'builder.add_children(node, {node1, {node2, node3}})'
-- adds 'node1', 'node2', and 'node3' as children of 'node'.
-- 'builder.add_children(node, "hello")'
-- adds a text node with "hello" as child of 'node'.
-- 'builder.add_children(node, node1)'
-- adds 'node1' as a child of 'node'.
-- THe parameter 'contains' is a table with boolean fields 'items',
-- 'blocks', 'inlines', and 'literal' that tells you what kind of
-- children the table can contain.
-- Nodes passed in that are appended are recorded in the table 'passed'.
-- The function returns 'true' or 'nil, msg'.
add_children = function(node, v, contains, passed)
  if type(v) == 'nil' then
    return true -- just skip a nil
  end
  if type(v) == 'table' then
    for _,x in ipairs(v) do
      local ok, msg = add_children(node, x, contains, passed)
      if not ok then
        return nil, msg
      end
    end
    return true
  elseif type(v) == 'function' then
    -- e.g. hard_break -- we want hard_break()
    local ok, msg = add_children(node, v(), contains, passed)
    return ok, msg
  end
  local child
  local created = false
  if type(v) == 'userdata' then
    child = v
  elseif contains.literal then
    if c.node_set_literal(node, tostring(v)) == 1 then
      return true
    else
      return nil, "Could not set literal"
    end
  else
    -- if v is not a node, make a text node:
    child = c.node_new(c.NODE_TEXT)
    created = true
    if c.node_set_literal(child, tostring(v)) ~= 1 then
      c.node_free(child)
      return nil, "Could not set literal"
    end
  end

  -- wrap the child in a paragraph and/or item if needed for it to fit in
  -- 'node'. 'wrapped' is the outermost node, which is appended to 'node',
  -- and 'parent' is the node the child is appended to.
  local child_class = node_get_class(child)
  local wrapped, parent = child, node
  local msg
  local direct = (child_class == 'item' and contains.items) or
                 (child_class == 'block' and contains.blocks) or
                 (child_class == 'inline' and contains.inlines)
  if direct then
    msg = "Could not append child"
  elseif child_class == 'block' and contains.items then
    wrapped = c.node_new(c.NODE_ITEM)
    parent = wrapped
    msg = "Could not append child to item"
  elseif child_class == 'inline' and contains.blocks then
    wrapped = c.node_new(c.NODE_PARAGRAPH)
    parent = wrapped
    msg = "Could not append child to para"
  elseif child_class == 'inline' and contains.items then
    wrapped = c.node_new(c.NODE_ITEM)
    parent = c.node_new(c.NODE_PARAGRAPH)
    c.node_append_child(wrapped, parent)
    msg = "Could not append child to para"
  else
    if created then
      c.node_free(child)
    end
    return nil, 'Tried to add a node with class ' .. child_class ..
                ' to a node with class ' .. node_get_class(node)
  end

  if wrapped == child or c.node_append_child(parent, child) == 1 then
    if c.node_append_child(node, wrapped) == 1 then
      if not created then
        passed[#passed + 1] = child
      end
      return true
    end
    if wrapped ~= child then
      msg = "Could not append " .. node_get_class(wrapped) .. " to node"
    end
  end

  -- on failure, free what was created here. A node that was passed in is
  -- left to the caller, and is detached only if it was moved into a wrapper
  -- (a failed append leaves it where it was).
  if wrapped ~= child then
    if c.node_parent(child) == parent then
      c.node_unlink(child)
    end
    c.node_free(wrapped)
  end
  if created then
    c.node_free(child)
  end
  return nil, msg
end

-- return children as a table
builder.get_children = function(node)
  local child = c.node_first_child(node)
  local result = {}
  while child do
    result[#result + 1] = child
    child = c.node_next(child)
  end
  return result
end

-- contains is a table, with boolean fields 'literal', 'blocks', 'inlines',
-- 'items'
local node = function(node_type, contains, fields)
  -- fields are set in a fixed order, so the error for invalid contents is
  -- deterministic
  local field_names = {}
  for field in pairs(fields or {}) do
    field_names[#field_names + 1] = field
  end
  table.sort(field_names)

  local function build(node, contents, passed)
    -- set the attributes if defined
    if type(contents) == 'table' then
      for _, field in ipairs(field_names) do
        if contents[field] then
          -- setters return 1 on success, or nil and a message
          local ok, msg = fields[field](node, contents[field])
          if ok ~= 1 then
            return nil, msg or ('Could not set ' .. field)
          end
        end
      end
    end
    -- treat rest as children
    return add_children(node, contents, contains, passed)
  end

  return function(contents)
    local node = c.node_new(node_type)
    if contents == nil then
      return node
    end
    local passed = {}
    local status, ok, msg = pcall(build, node, contents, passed)
    if status and ok then
      return node
    end
    -- on failure, or an error raised while building, return the nodes passed
    -- in to the caller and free the rest
    for _, child in ipairs(passed) do
      c.node_unlink(child)
    end
    c.node_free(node)
    if not status then
      error(ok, 0)
    end
    return nil, msg
  end
end

local function set_tight(n, tight)
  local t_int = tight and 1 or 0
  return c.node_set_list_tight(n, t_int)
end

local function set_delim(n, delim)
  local delimt
  if delim == c.PAREN_DELIM or delim == c.PERIOD_DELIM then
    delimt = delim
  elseif delim == ')' then
    delimt = c.PAREN_DELIM
  elseif delim == '.' then
    delimt = c.PERIOD_DELIM
  else
    return nil, 'Unknown delimiter ' .. tostring(delim)
  end
  return c.node_set_list_delim(n, delimt)
end

builder.document = node(c.NODE_DOCUMENT, {blocks = true})

builder.block_quote = node(c.NODE_BLOCK_QUOTE, {blocks = true})

local ordered_list = node(c.NODE_LIST, {items = true},
                 {delim = set_delim,
                  start = c.node_set_list_start,
                  tight = set_tight,
                 })

builder.ordered_list = function(contents)
  local n, msg = ordered_list(contents)
  if not n then
    return nil, msg
  end
  c.node_set_list_type(n, c.ORDERED_LIST)
  return n
end

local bullet_list = node(c.NODE_LIST, {items = true},
                 {tight = set_tight,
                 })

builder.bullet_list = function(contents)
  local n, msg = bullet_list(contents)
  if not n then
    return nil, msg
  end
  c.node_set_list_type(n, c.BULLET_LIST)
  return n
end

builder.item = node(c.NODE_ITEM, {blocks = true})

builder.code_block = node(c.NODE_CODE_BLOCK, {literal = true},
   { info = c.node_set_fence_info })

builder.html_block = node(c.NODE_HTML_BLOCK, {literal = true})

builder.custom_block = node(c.NODE_CUSTOM_BLOCK,
   {inlines = true, blocks = true, items = true},
   { on_enter = c.node_set_on_enter, on_exit = c.node_set_on_exit })

builder.thematic_break = node(c.NODE_THEMATIC_BREAK)

builder.heading = node(c.NODE_HEADING, {inlines = true},
  { level = c.node_set_heading_level })

builder.paragraph = node(c.NODE_PARAGRAPH, {inlines = true})

builder.text = node(c.NODE_TEXT, {literal = true})

builder.emph = node(c.NODE_EMPH, {inlines = true})

builder.strong = node(c.NODE_STRONG, {inlines = true})

builder.link = node(c.NODE_LINK, {inlines = true},
                 {title = c.node_set_title, url = c.node_set_url})

builder.image = node(c.NODE_IMAGE, {inlines = true},
                 {title = c.node_set_title, url = c.node_set_url})

builder.linebreak = node(c.NODE_LINEBREAK)

builder.softbreak = node(c.NODE_SOFTBREAK)

builder.code = node(c.NODE_CODE, {literal = true})

builder.html_inline = node(c.NODE_HTML_INLINE, {literal = true})

builder.custom_inline = node(c.NODE_CUSTOM_INLINE, {inlines = true},
   { on_enter = c.node_set_on_enter, on_exit = c.node_set_on_exit })

return builder
