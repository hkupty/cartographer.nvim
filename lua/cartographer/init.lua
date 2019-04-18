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
  folder = {
    search_command = "find -type d -not -path './.git/*' -not -name '\\.*'"
  },
  rx = {
    search_command = "find . -not -path '*/\\.*' -type f | xargs grep -nHE "
  }
}
local cache = {}
local low_level = {}
local cartographer = {}

-- TODO hacke
cartographer.cache = cache

low_level.new_impromptu_filter = function(obj)
  local impromptu_opts = {
    title = "🧭 " .. obj.title .. " [" .. obj.address .. "]",
    options = {},
    mappings = obj.mappings,
    handler = obj.handler
  }
  local ui
  if obj.session ~= nil then
    ui = impromptu.new.filter(impromptu_opts)
    obj.session:stack(ui)
  else
    ui = impromptu.filter(impromptu_opts)
  end
  local ui_id = ui.session_id

  cache[ui_id] = {
    buffer = {},
    ui = ui,
  }

  return ui_id

end

low_level.create_filter = function(obj)
  local ui_id = low_level.new_impromptu_filter(obj)
  local stdout_handler = low_level.defn((obj.local_handler or "handle"), ui_id)

  local job = nvim.nvim_call_function("jobstart", {
      obj.search_command, {
        on_stdout = stdout_handler,
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
        ln = match()
      }
    end
  end
end

cartographer.project = function()
  low_level.create_filter{
    title = "Select project",
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
    title = "Select file",
    address = cwd,
    search_command = configuration.files.search_command,
    handler = function(_, ret)
      nvim.nvim_command(winnr .. "wincmd w | " .. (open_cmd or "edit") .. " " .. cwd .. "/" .. ret.description)
      return true
    end
  }
end

cartographer.local_buffers = function()
  local cb = nvim.nvim_get_current_buf()
  local winnr = nvim.nvim_call_function("bufwinnr", {cb})
  local cwd = nvim.nvim_call_function("getcwd", {})
  local path_starts_with = function(bufnr)

    return util.starts_with(cwd, vim.api.nvim_call_function("expand", {"#" .. bufnr .. ":p"}))
  end

  local ui_id = low_level.new_impromptu_filter{
    title = "Local buffers",
    address = cwd,
    handler = function(_, ret)
      nvim.nvim_command(winnr .. "wincmd w | b" .. ret.bufnr)
      return true
    end

  }

  for _, buffer in util.filter(path_starts_with,
      util.filter(vim.api.nvim_buf_is_loaded,
        vim.api.nvim_list_bufs()
    )) do
    cache[ui_id].ui:update{
      description = vim.api.nvim_call_function("expand", {"#" .. buffer .. ":p"}),
      bufnr = buffer
    }
  end

end

cartographer.buffers = function()
  local cb = nvim.nvim_get_current_buf()
  local winnr = nvim.nvim_call_function("bufwinnr", {cb})
  local cwd = nvim.nvim_call_function("getcwd", {})

  local ui_id = low_level.new_impromptu_filter{
    title = "Local buffers",
    address = cwd,
    handler = function(_, ret)
      nvim.nvim_command(winnr .. "wincmd w | b" .. ret.bufnr)
      return true
    end

  }

  for _, buffer in util.filter(vim.api.nvim_buf_is_loaded, vim.api.nvim_list_bufs()) do
    cache[ui_id].ui:update{
      description = vim.api.nvim_call_function("expand", {"#" .. buffer .. ":p"}),
      bufnr = buffer
    }
  end

end

cartographer.do_at = function(handler)
  local cwd = nvim.nvim_call_function("getcwd", {})
  low_level.create_filter{
    title = "Select folder",
    address = cwd,
    search_command = configuration.folder.search_command,
    handler = handler
  }
end

cartographer.todo = function(open_cmd)
  local cb = nvim.nvim_get_current_buf()
  local winnr = nvim.nvim_call_function("bufwinnr", {cb})
  local cwd = nvim.nvim_call_function("getcwd", {})

  low_level.create_filter{
    title = "Project TODOs",
    address = cwd,
    search_command = configuration.rx.search_command .. " '(TODO|HACK|FIXME)'",
    handler = function(_, ret)
      nvim.nvim_command(
        winnr .. "wincmd w | " ..
        (open_cmd or "edit") .. '+' .. ret.ln .. " " .. cwd .. "/" .. ret.fpath
      )
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
    title = "Find",
    address = cwd,
    search_command = configuration.rx.search_command .. " '" .. regex .. "'",
    handler = function(_, ret)
      nvim.nvim_command(
        winnr .. "wincmd w | " ..
        (open_cmd or "edit") .. '+' .. ret.ln .. " " .. cwd .. "/" .. ret.fpath
      )
      return true
    end,
    local_handler = "handle_vimgrep"
  }
end

cartographer.cd = function()
  local cwd = nvim.nvim_call_function("getcwd", {})
  cartographer.do_at(function(_, ret)
      nvim.nvim_command("tcd " .. cwd .. "/" .. ret.description)
      return true
  end)
end

cartographer.dbg = function()
  print(require("inspect")(cache))
end

return cartographer
