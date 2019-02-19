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

return util
