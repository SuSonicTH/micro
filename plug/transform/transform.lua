VERSION = "0.1.0"

local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")

function getText(a, b)
    local txt, buf = {}, micro.CurPane().Buf

    -- Editing a single line?
    if a.Y == b.Y then
        return buf:Line(a.Y):sub(a.X+1, b.X)
    end

    -- Add first part of text selection (a.X+1 as Lua is 1-indexed)
    table.insert(txt, buf:Line(a.Y):sub(a.X+1))

    -- Stuff in the middle
    for lineNo = a.Y+1, b.Y-1 do
        table.insert(txt, buf:Line(lineNo))
    end

    -- Insert last part of selection
    table.insert(txt, buf:Line(b.Y):sub(1, b.X))

    return table.concat(txt, "\n")
end

local function replace_selection(replacement, whole_lines, no_selection_all_text)
  whole_lines = whole_lines == nil and true or whole_lines
  no_selection_all_text = no_selection_all_text == nil and true or no_selection_all_text

  local pane = micro.CurPane()
  local cursor =  pane.Cursor
  local from, to
  
  if cursor:HasSelection() then
    if cursor.CurSelection[1]:GreaterThan(-cursor.CurSelection[2]) then
      from, to = cursor.CurSelection[2], cursor.CurSelection[1]
    else
      from, to = cursor.CurSelection[1], cursor.CurSelection[2]
    end
    
	if whole_lines then 
		from.X = 0
		to.X = string.len(pane.Buf:Line(to.Y))
	end
    
    from,to = buffer.Loc(from.X, from.Y), buffer.Loc(to.X, to.Y)
  elseif no_selection_all_text then
      from, to = buffer.Loc(0, 0), buffer.Loc(math.huge, math.huge)
  else 
    return --todo: show error nothing selected
  end

  local oldText = getText(from, to)
  print(oldText)
  local newText = replacement(oldText)
  if type(newText) == 'table' then
    newText = table.concat(newText, "\n")
  end
    
  pane.Buf:Replace(from, to, newTxt)

  if cursor:HasSelection() then
    local diff = string.len(newTxt) - string.len(oldTxt)
    if diff ~= 0 then
      if cursor.CurSelection[1]:GreaterThan(-cursor.CurSelection[2]) then
        cursor.CurSelection[1].X = cursor.CurSelection[1].X - d
      else
        cursor.CurSelection[2].X = cursor.CurSelection[2].X + d
      end
    end
  end
  
end

local function lines(text)
  return (text .. "\n"):gmatch("(.-)\n")
end

local function unique(text)
  local unique = {}
  local out = {}
  for line in lines(text) do
    if unique[line] == nil then
      unique[line] = true
      table.insert(out, line)
    end
  end
  return out
end

local function sort(text)
  local out = {}
  for line in lines(text) do
    table.insert(out, line)
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

local function each_line(process)
  return function(text)
    local out = {}
    for line in lines(text) do
      table.insert(out, process(line))
    end
    return out
  end
end

local trim=function(line) return (line:gsub("^%s*(.-)%s*$", "%1")) end
local trim_left=function(line) return (line:gsub("^%s*(.-)$", "%1")) end
local trim_right=function(line) return (line:gsub("^(.-)%s*$", "%1")) end

local function line_to_columns(text, separator, remove_quoutes)
  local q = remove_quoutes and 1 or 0
  text = text .. separator
  local ret = {}
  local fieldstart = 1
  repeat
    if text:find('^"', fieldstart) then
      local a, c
      local i  = fieldstart
      repeat
        -- find closing quote
        a, i, c = text:find('"("?)', i + 1)
      until c ~= '"'    -- quote not followed by quote?
      if not i then error('unmatched "') end
      local f = text:sub(fieldstart + q, i - q)
      table.insert(ret, (string.gsub(f, '""', '"')))
      fieldstart = text:find(separator, i) + 1
    else                -- unquoted; find next comma
      local nexti = text:find(separator, fieldstart)
      table.insert(ret, text:sub(fieldstart, nexti-1))
      fieldstart = nexti + 1
    end
  until fieldstart > string.len(text)
  return ret
end


local function to_table(text, from, remove_quoutes, to, prefix, suffix)
  prefix = prefix or ""
  suffix = suffix or ""
  
  local data = {}
  local max_width = {}
  
  for line in lines(text) do
    local columns = line_to_columns(line, from, remove_quoutes)
    table.insert(data, columns)
    for i,v in ipairs(columns) do
      if max_width[i] == nil or v:len() > max_width[i] then 
        max_width[i] = v:len()
      end
    end
  end
  
  local space={}
  local width={}
  for i,v in ipairs(max_width) do
    space[i] = String.rep(" ", v)
    width[i] = max_width[i] * -1
  end

  local out = {}
  for _,columns in ipairs(data) do
    local line ={}
    for i,v in ipairs(columns) do
     table.insert(line, string.sub(space[i]..v, width[i]))
    end
     table.insert(out, out, prefix .. table.concat(line, to) .. suffix)
  end

  return out
end

local function from_table(text, from, to)
  local out = {}
  for line in lines(text) do
    local columns = line_to_columns(line, from, true)
    local line = {}

    for i,column in ipairs(columns) do
      if from ~= '|' or i > 1 then 
        column = trim(column)
        if (column:find('"')) then
          column ='"' .. column:gsub('"','""') .. '"'
        elseif (column:find(to)) then
          column ='"' .. column .. '"'
        end 
        table.insert(line, column)
      end
    end

    table.insert(out, table.concat(line, to))
  end

  return out
end

function init()
    config.MakeCommand("unique", function() replace_selection(unique, true, true, false)  end, config.NoComplete)
    config.MakeCommand("sort", function() replace_selection(sort, true, true, false)  end, config.NoComplete)
    config.MakeCommand("trim-right", function() replace_selection(each_line(trim_right), true, true, true)  end, config.NoComplete)
    config.MakeCommand("trim-left", function() replace_selection(each_line(trim_left), true, true, true)  end, config.NoComplete)
    config.MakeCommand("trim", function() replace_selection(each_line(trim), true, true, true)  end, config.NoComplete)
    config.MakeCommand("csv-to-table", function() replace_selection(function(text) return to_table(text, ',', true, ' | ', '| ', ' |') end, true, true, false)  end, config.NoComplete)
    config.MakeCommand("csv-equal-with", function() replace_selection(function(text) return to_table(text, ',', false, ', ') end, true, true, false)  end, config.NoComplete)
    config.MakeCommand("table-to-csv", function() replace_selection(function(text) return from_table(text, '|', ',') end, true, true, false)  end, config.NoComplete)
    config.MakeCommand("csv-trim", function() replace_selection(function(text) return from_table(text, ',', ',') end, true, true, false)  end, config.NoComplete)
  
    config.AddRuntimeFile("transform", config.RTHelp, "help/transform.md")
end

