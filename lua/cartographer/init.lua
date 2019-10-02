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
  },
  search = {
    search_command = "find . -not -path '*/\\.*' -type f | xargs grep -nHEF --"
  },
  branches = {
    search_command = "git branch"
  },
  dirty = {
    search_command = "git status --porcelain | awk '{print $NF}'"
  }

}
local cache = {}
local low_level = {}
local cartographer = {}

-- TODO hacke
cartographer.cache = cache

low_level.create_filter = function(obj)
  local impromptu_opts = {
    title = "🧭 " .. obj.title .. " [" .. obj.address .. "]",
    options = {},
    mappings = obj.mappings,
    handler = obj.handler
  }
  local ui
  obj.ui = impromptu.new.filter(impromptu_opts)

  if obj.session == nil then
    obj.session = impromptu.session()
  end

  obj.session:set("cwd", obj.address)

  obj.session:stack(obj.ui):render()
  local ui_id = obj.session.session_id

  obj.session:set("cartographer_ui_id", ui_id)
  obj.session:set("cartographer_address", obj.address)

  local stdout_handler = low_level.defn((obj.local_handler or "handle"), ui_id)

  cache[ui_id] = {
    buffer = {},
    ui = obj.ui,
    session = obj.session
  }

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
      cache[ui_id].ui.update(cache[ui_id].session, {description = line})
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

cartographer.dirty = function(open_cmd)
  local cb = nvim.nvim_get_current_buf()
  local winnr = nvim.nvim_call_function("bufwinnr", {cb})
  local cwd = vim.trim(nvim.nvim_call_function("system", {"git rev-parse --show-toplevel"}))

  low_level.create_filter{
    title = "Select file",
    address = cwd,
    search_command = configuration.dirty.search_command,
    handler = function(_, ret)
      nvim.nvim_command(winnr .. "wincmd w | " .. (open_cmd or "edit") .. " " .. cwd .. "/" .. ret.description)
      return true
    end
  }
end


cartographer.checkout = function(open_cmd)
  local cb = nvim.nvim_get_current_buf()
  local winnr = nvim.nvim_call_function("bufwinnr", {cb})
  local cwd = vim.trim(nvim.nvim_call_function("system", {"git rev-parse --show-toplevel"}))

  low_level.create_filter{
    title = "Select branch",
    address = cwd,
    search_command = configuration.branches.search_command,
    handler = function(_, ret)
      nvim.nvim_call_function("system", {"git checkout " .. ret.description})
      return true
    end
  }
end

cartographer.do_at = function(handler)
  local cwd = nvim.nvim_call_function("getcwd", {})
  local payload

  local function this_handler(session, selected)
    if selected == "__up_dir" then
      session.hls = {}
      vim.api.nvim_call_function("chanclose", {cache[session.cartographer_ui_id].job})
      low_level.create_filter(payload(util.dir_up(session.cartographer_address), session))
      return false
    else
      return handler(session, selected)
    end
  end
  payload = function(address, session)
    local ret ={
      title = "Select folder",
      search_command = configuration.folder.search_command,
      address = address,
      handler = this_handler,
      mappings = {['<C-h>'] = "__up_dir"}
    }
    if session ~= nil then
      ret.session = session
    end
    return ret
  end

  low_level.create_filter(payload(cwd))
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
  cartographer.do_at(function(session, ret)
      nvim.nvim_command("tcd " .. session.cwd .. "/" .. ret.description)
      return true
  end)
end

cartographer.search = function(parameter, open_cmd, winnr)
  if winnr == nil then
    local cb = nvim.nvim_get_current_buf()
    winnr = nvim.nvim_call_function("bufwinnr", {cb})
  end
  local cwd = nvim.nvim_call_function("getcwd", {})

  low_level.create_filter{
    title = "Searching for '" .. parameter .. "'",
    address = cwd,
    search_command = configuration.search.search_command .. " '" .. parameter .. "'",
    handler = function(_, ret)

      nvim.nvim_command(
        winnr .. "wincmd w | " ..
        (open_cmd or "edit") .. ' +' .. ret.ln .. " " .. cwd .. "/" .. ret.fpath
      )
      return true
    end,
    local_handler = "handle_vimgrep"
  }
end

cartographer.buffers = function(opts)
  local winnr = nvim.nvim_call_function("bufwinnr", {0})
  local filter = opts.filter or ""

  local impromptu_opts = {
    title = "🧭 Buffers",
    options = {},
    handler = function(_, ret)
      nvim.nvim_command(winnr .. "wincmd w | " ..  (opts.open_cmd or "edit") .. ret.fpath)
      return true
    end
  }
  local session = impromptu.filter(impromptu_opts)
  for _, id in ipairs(vim.api.nvim_list_bufs()) do
    local buf = vim.api.nvim_call_function("getbufinfo", {id})
    local name = buf.name

    if name ~= nil and util.starts_with(name, filter) then
      session:update{description = name, id = id, fpath = name}
    end
  end
end

cartographer.dbg = function()
  print(require("inspect")(cache))
end

return cartographer
