local util = {}

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

util.filter = function(predicate, iter_or_coll, coll, i)
  if type(iter_or_coll) == "table" then
    coll = iter_or_coll
    iter_or_coll = next
    i = nil
  end

  local function inner(seq, ix)
    local nix, ret = iter_or_coll(seq, ix)
    if ret == nil then
      return
    elseif predicate(ret) then
      return nix, ret
    else
      return inner(seq, nix)
    end
  end
  return inner, coll, i
end

util.map = function(fn, iter_or_coll, coll, i)
  if type(iter_or_coll) == "table" then
    coll = iter_or_coll
    iter_or_coll = next
    i = nil
  end

  local function inner(seq, ix)
    local nix, ret = iter_or_coll(seq, ix)
    if ret == nil then
      return
    else
      return nix, fn(ret)
    end
  end

  return inner, coll, i
end

util.realize = function(iter, coll)
  local tbl = {}
  for ix, v in iter, coll do
    tbl[ix] = v
  end
  return tbl
end

util.starts_with = function(prefix, str)
  return prefix == "" or string.sub(str, 1, #prefix) == prefix
end

return util
