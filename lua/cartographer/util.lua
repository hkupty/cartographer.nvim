local util = {}

util.path_to_table = function(path)
  local tbl = {""}
  for node in path:gmatch("[^/]+") do
    table.insert(tbl, node)
  end
  return tbl
end

util.drop_last = function(tbl)
  local sz = #tbl - 1
  local nxt = function(t, ix)
    if ix == nil or ix < sz then
      return next(t, ix)
    end
  end

  local new = {}
  for _, v in nxt, tbl do
    table.insert(new, v)
  end

  return new
end

util.dir_up = function(path)
   return table.concat(util.drop_last(util.path_to_table(path)), "/")
end

util.update = function(dict, key, fn)
  if fn ~= nil then
    dict[key] = fn(dict[key])
  end
  return dict
end

util.merge = function(...)
  local new = {}

  for i = 1, select('#', ...) do
    local tbl = select(i, ...)

    if tbl ~= nil then
      for k, v in pairs(tbl) do
        new[k] = v
      end
      for k, v in ipairs(tbl) do
        new[k] = v
      end
    end
  end

  new = setmetatable(new, nil)

  return new
end

-- Taken from luarocks
util.deep_merge = function(dst, src)
   for k, v in pairs(src) do
      if type(v) == "table" then
         if not dst[k] then
            dst[k] = {}
         end
         if type(dst[k]) == "table" then
            util.deep_merge(dst[k], v)
         else
            dst[k] = v
         end
      else
         dst[k] = v
      end
   end
   return dst
end

util.clone = function(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[util.clone(orig_key)] = util.clone(orig_value)
        end
        setmetatable(copy, util.clone(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

util.safe_merge = function(to, from)
  return util.deep_merge(util.clone(to), from)
end

util.map = function(tbl, fn)
  local new = {}

  for _, v in ipairs(tbl) do
    local ret = fn(v)
    if ret ~= nil then
      table.insert(new, ret)
    end
  end

  return new
end

util.starts_with = function(str, begining)
  return begining == "" or string.sub(str, 1, #begining) == begining
end

return util
