-- luacheck: globals vim
local cache = require("cartographer.cache")
local impromptu = require("impromptu")
local low_level = {}

low_level.create_filter = function(obj)
  local key

  if obj.reopen ~= nil then
    key = obj.reopen()
    local reverse = key ~= nil and cache.reverse[key]
    if reverse ~= nil then
      impromptu.recent[reverse]:render()
      return
    end
  end

  local impromptu_opts = {
    title = "🧭 " .. obj.title .. " [" .. obj.path .. "]",
    options = {},
    mappings = obj.mappings,
    handler = obj.handler
  }
  obj.ui = impromptu.new.filter(impromptu_opts)

  if obj.session == nil then
    obj.session = impromptu.session()
  end

  obj.session:stack(obj.ui):render()
  local ui_id = obj.session.session_id

  obj.session:set("cartographer_ui_id", ui_id)

  cache[ui_id] = {
    buffer = {},
    ui = obj.ui,
    session = obj.session
  }

  if key ~= nil then
    cache.reverse[key] = ui_id
  end



  if obj._type == "job" then
    local job = vim.fn.jobstart(
        obj:prepare(), {
          on_stdout = function(_, dt) obj.local_handler(ui_id, dt) end,
          cwd = obj.path
        }
    )

    cache[ui_id].job = job
  end

  if obj.custom ~= nil then
    local c
    if type(obj.custom) == "table" then
      c = obj.custom
    elseif type(obj.custom) == "function" then
      c = obj:custom()
    end

    for _, custom in ipairs(c) do
      obj.ui.update(obj.session, custom)
    end
  end

  return cache[ui_id]
end

low_level.handle = function(ui_id, dt)
  if cache[ui_id].ui.destroyed then
    vim.fn.chanclose(cache[ui_id].job)
  else
    for _, line in ipairs(dt) do
      cache[ui_id].session:update{
        description = line,
        path = line
      }
    end
  end
end

low_level.handle_vimgrep = function(ui_id, dt)
  if cache[ui_id].ui.destroyed then
    vim.fn.chanclose(cache[ui_id].job)
  else
    for _, line in ipairs(dt) do
      if line ~= "" then
        local match = line:gmatch("[^:]+")
        cache[ui_id].session:update{
          path = match(),
          ln = match(),
          col = match(),
          description = match()
        }
      end
    end
  end
end

return low_level
