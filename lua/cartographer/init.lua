-- luacheck: globals vim
local nvim = vim.api
local util = require("cartographer.util")
local impromptu = require("impromptu")
local configuration = {
  project = {
    root = "$HOME/code",
    search_command = "find -type d -name '.git' -maxdepth 3 -printf '%h\\n'"
  },
  files = {
    search_command = "find -type f"
  },
  rx = {
    search_command = "find . -not -path '*/\\.*' -type f | xargs grep -nHE "
  }
}
local cache = {}
local low_level = {}
local cartographer = {}

low_level.create_filter = function(obj)
  local ui = impromptu.filter{
    title = "▢ Select project [" .. obj.address .. "]",
    options = {},
    handler = obj.handler
  }
  local ui_id = ui.session_id
  cache[ui_id] = {
    buffer = {},
    ui = ui,
  }

  local job = nvim.nvim_call_function("jobstart", {
      obj.search_command, {
        on_stdout = low_level.defn((obj.local_handler or "handle"), ui_id),
        cwd = obj.address
      }
    }
  )

  cache[ui_id].job = job

  return cache[ui_id]
end

low_level.defn = function(fn_name, ui_id)
  local name = "Cart_" .. fn_name .. ui_id
  -- TODO fix super hack
  local fn = {
  'function! ' .. name .. '(c, dt, s)',
    'call luaeval("require(\'cartographer\').' .. fn_name .. '(' .. ui_id .. ', _A)", a:dt)',
  'endfunction'
  }

  nvim.nvim_call_function("execute", {fn})

  return name
end

cartographer.config = function(obj)
  configuration = util.deep_merge(configuration, obj)
end

cartographer.handle = function(ui_id, dt)
  if cache[ui_id].ui.destroyed then
    nvim.nvim_call_function("chanclose", {cache[ui_id].job})
  else
    for _, line in ipairs(dt) do
      cache[ui_id].ui:update{description = line}
    end
  end
end

cartographer.handle_vimgrep = function(ui_id, dt)
  if cache[ui_id].ui.destroyed then
    nvim.nvim_call_function("chanclose", {cache[ui_id].job})
  else
    for _, line in ipairs(dt) do
      local match = line:gmatch("[^:]+")
      cache[ui_id].ui:update{
        description = line,
        fpath = match(),
        ln = match(),
        column = match()
      }
    end
  end
end

cartographer.project = function()
  low_level.create_filter{
    address = configuration.project.root,
    search_command = configuration.project.search_command,
    handler = function(_, ret)
      nvim.nvim_command("tcd " .. configuration.project.root .. "/" .. ret.description)
      return true
    end,
  }
end

cartographer.files = function(open_cmd)
  local cb = nvim.nvim_get_current_buf()
  local winnr = nvim.nvim_call_function("bufwinnr", {cb})
  local cwd = nvim.nvim_call_function("getcwd", {})

  low_level.create_filter{
    address = cwd,
    search_command = configuration.files.search_command,
    handler = function(_, ret)
      nvim.nvim_command(winnr .. "wincmd w | " .. (open_cmd or "edit") .. " " .. cwd .. "/" .. ret.description)
      return true
    end
  }
end

cartographer.todo = function(open_cmd)
  local cb = nvim.nvim_get_current_buf()
  local winnr = nvim.nvim_call_function("bufwinnr", {cb})
  local cwd = nvim.nvim_call_function("getcwd", {})

  low_level.create_filter{
    address = cwd,
    search_command = configuration.rx.search_command .. " '(TODO|FIXME)'",
    handler = function(_, ret)
      nvim.nvim_command(winnr .. "wincmd w | " .. (open_cmd or "edit") .. '+' .. ret.ln .. " " .. cwd .. "/" .. ret.fpath)
      return true
    end,
    local_handler = "handle_vimgrep"
  }
end

cartographer.rx = function(regex, open_cmd)
  local cb = nvim.nvim_get_current_buf()
  local winnr = nvim.nvim_call_function("bufwinnr", {cb})
  local cwd = nvim.nvim_call_function("getcwd", {})

  low_level.create_filter{
    address = cwd,
    search_command = configuration.rx.search_command .. " '" .. regex .. "'",
    handler = function(_, ret)
      nvim.nvim_command(winnr .. "wincmd w | " .. (open_cmd or "edit") .. '+' .. ret.ln .. " " .. cwd .. "/" .. ret.fpath)
      return true
    end,
    local_handler = "handle_vimgrep"
  }
end

cartographer.dbg = function()
  print(require("inspect")(cache))
end

return cartographer
