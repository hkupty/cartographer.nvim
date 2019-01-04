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
  }
}
local cache = {}
local low_level = {}
local cartographer = {}


low_level.defn = function(ui_id)
  local name = "Handle" .. ui_id
  -- TODO fix super hack
  local fn = {
  'function! ' .. name .. '(c, dt, s)',
    'call luaeval("require(\'cartographer\').handle(' .. ui_id .. ', _A)", a:dt)',
  'endfunction'
  }

  nvim.nvim_call_function("execute", {fn})

  return name
end

cartographer.config = function(obj)
  configuration = util.deep_merge(configuration, obj)
end

cartographer.handle = function(ui_id, dt)
  for _, v in ipairs(dt) do
    cache[ui_id].ui:update{description = v}
  end
end

cartographer.project = function()
  local ui = impromptu.filter{
    title = "▢ Select project [" .. configuration.project.root .. "]",
    options = {},
    handler = function(_, ret)
      nvim.nvim_command("tcd " .. configuration.project.root .. "/" .. ret.description)
      return true
    end
  }
  local ui_id = ui.session_id
  cache[ui_id] = {
    ui = ui,
  }

  local job = nvim.nvim_call_function("jobstart", {
      configuration.project.search_command, {
        on_stdout = low_level.defn(ui_id),
        cwd = configuration.project.root
      }
    }
  )

  cache[ui_id].job = job
end

cartographer.files = function(open_cmd)
  local cwd = nvim.nvim_call_function("getcwd", {})
  local ui = impromptu.filter{
    title = "▢ Select file [" .. cwd .. "]",
    options = {},
    handler = function(_, ret)
      nvim.nvim_command((open_cmd or "edit") .. " " .. cwd .. "/" .. ret.description)
      return true
    end
  }
  local ui_id = ui.session_id
  cache[ui_id] = {
    ui = ui,
  }

  local job = nvim.nvim_call_function("jobstart", {
      configuration.files.search_command, {
        on_stdout = low_level.defn(ui_id),
        cwd = cwd
      }
    }
  )

  cache[ui_id].job = job
end

cartographer.dbg = function()
  print(require("inspect")(cache))
end

return cartographer
