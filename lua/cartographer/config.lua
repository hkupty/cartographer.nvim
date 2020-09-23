local util = require("cartographer.util")
local config = {}

config._data = {}

config.set = function(obj)
  config._data = util.deep_merge(config._data, obj)
end

config.data = setmetatable({}, {__index = function(_, key)
  local result = config._data[key]
  if result == nil then
    return {}
  end
  return result
end})

return config
