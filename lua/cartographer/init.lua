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

local cache = {
  reverse = {}
}
local low_level = {}
local cartographer = {}

cartographer.proxy = setmetatable({}, {
  __index = function(_, key)
    return function(obj)
      return cartographer[key](util.deep_merge(configuration[key] or {}, obj))
    end
  end
})

-- TODO hacke
cartographer.cache = cache

low_level.create_filter = function(obj)
  local key = (obj.type or "~") .. ":" .. obj.address
  --local reverse = cache.reverse[key]
  --if reverse ~= nil and obj.reopen ~= false then
    --impromptu.recent[reverse]:render()
    --return
  --end

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

  local stdout_handler = (obj.local_handler or cartographer.handle)

  cache[ui_id] = {
    buffer = {},
    ui = obj.ui,
    session = obj.session
  }

  cache.reverse[key] = ui_id

  local job = vim.fn.jobstart(
      obj.search_command, {
        on_stdout = function(_, dt) stdout_handler(ui_id, dt) end,
        cwd = obj.address
      }
  )

  cache[ui_id].job = job

  if obj.custom ~= nil then
    for _, custom in ipairs(obj.custom) do
      obj.ui.update(obj.session, custom)
    end
  end

  return cache[ui_id]
end

cartographer.config = function(obj)
  configuration = util.deep_merge(configuration, obj)
end

cartographer.handle = function(ui_id, dt)
  if cache[ui_id].ui.destroyed then
    vim.fn.chanclose(cache[ui_id].job)
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
      cache[ui_id].session:update{
        description = line,
        fpath = match(),
        ln = match()
      }
    end
  end
end

cartographer.project = function(opt)
  low_level.create_filter{
    type = "project",
    title = "Select project",
    address = opt.root,
    search_command = opt.search_command,
    handler = function(_, ret)
      nvim.nvim_command("tcd " .. configuration.project.root .. "/" .. ret.description)
      return true
    end,
  }
end

-- v1
cartographer.files = function(opt)
  local winnr = nvim.nvim_get_current_win()

  local job = cartographer.do_at{
    title = "Select file",
    search_command = opt.search_command,
    custom = opt.custom,
    handler = function(session, ret)
      nvim.nvim_set_current_win(winnr)

      if ret.self_handler ~= nil then
        return ret.self_handler()
      elseif opt.handler ~= nil and opt.handler(ret) then
        return true
      else
        nvim.nvim_command((opt.open_cmd or "edit") .. " " .. session.cwd .. "/" .. ret.description)
      end
      return true
    end
  }
  return job

end

-- v1
cartographer.dirty = function(opt)
  local winnr = nvim.nvim_get_current_win()
  local cwd = vim.trim(nvim.nvim_call_function("system", {"git rev-parse --show-toplevel"}))

  low_level.create_filter{
    title = "Select file",
    address = cwd,
    search_command = opt.search_command,
    handler = function(_, ret)
      nvim.nvim_set_current_win(winnr)
      nvim.nvim_command((opt.open_cmd or "edit") .. " " .. cwd .. "/" .. ret.description)
      return true
    end
  }
end


-- v1
cartographer.checkout = function(opt)
  local winnr = nvim.nvim_get_current_win()
  local cwd = vim.trim(nvim.nvim_call_function("system", {"git rev-parse --show-toplevel"}))

  low_level.create_filter{
    title = "Select branch",
    address = cwd,
    search_command = opt.search_command,
    handler = function(_, ret)
      nvim.nvim_call_function("system", {"git checkout " .. ret.description})
      return true
    end
  }
end

-- v1
cartographer.do_at = function(obj)
  local cwd = nvim.nvim_call_function("getcwd", {})
  local payload

  local function this_handler(session, selected)
    if selected == "__up_dir" or selected.action == "__up_dir" then
      session.hls = {}
      vim.api.nvim_call_function("chanclose", {cache[session.cartographer_ui_id].job})
      low_level.create_filter(payload(util.dir_up(session.cartographer_address), session))
      return false
    else
      return obj.handler(session, selected)
    end
  end
  payload = function(address, session)
    local ret = {
      title = obj.title,
      custom = obj.custom,
      search_command = obj.search_command,
      address = address,
      handler = this_handler,
      mappings = {['<C-h>'] = "__up_dir"}
    }
    if session ~= nil then
      ret.session = session
    end
    return ret
  end

  return low_level.create_filter(payload(cwd))
end

-- v1
cartographer.todo = function(open_cmd)
  local winnr = nvim.nvim_get_current_win()
  local cwd = nvim.nvim_call_function("getcwd", {})

  low_level.create_filter{
    title = "Project TODOs",
    address = cwd,
    search_command = configuration.rx.search_command .. " '(TODO|HACK|FIXME)'",
    handler = function(_, ret)
      nvim.nvim_set_current_win(winnr)
      nvim.nvim_command(
        (open_cmd or "edit") .. '+' .. ret.ln .. " " .. cwd .. "/" .. ret.fpath
      )
      return true
    end,
    local_handler = cartographer.handle_vimgrep
  }
end

-- TODO migrate
cartographer.rx = function(regex, open_cmd)
  local winnr = nvim.nvim_get_current_win()
  local cwd = nvim.nvim_call_function("getcwd", {})

  low_level.create_filter{
    title = "Find",
    address = cwd,
    search_command = configuration.rx.search_command .. " '" .. regex .. "'",
    handler = function(_, ret)
      nvim.nvim_set_current_win(winnr)
      nvim.nvim_command(
        (open_cmd or "edit") .. '+' .. ret.ln .. " " .. cwd .. "/" .. ret.fpath
      )
      return true
    end,
    local_handler = cartographer.handle_vimgrep
  }
end

-- v1
cartographer.cd = function()
  cartographer.do_at{
    title = "Select folder",
    search_command = configuration.folder.search_command,
    custom = {
          {description = "."},
          {description = "..", action = "__up_dir"}
        },
    handler = function(session, ret)
      nvim.nvim_command("tcd " .. session.cwd .. "/" .. ret.description)
      return true
  end}
end

-- TODO migrate
cartographer.search = function(opt)
  if opt.winnr == nil then
    opt.winnr = nvim.nvim_get_current_win()
  end
  local cwd = nvim.nvim_call_function("getcwd", {})

  low_level.create_filter{
    title = "Searching for '" .. opt.parameter .. "'",
    address = cwd,
    search_command = opt.search_command .. " '" .. opt.parameter .. "'",
    handler = function(_, ret)
      nvim.nvim_set_current_win(opt.winnr)
      nvim.nvim_command((opt.open_cmd or "edit") .. ' +' .. ret.ln .. " " .. cwd .. "/" .. ret.fpath
      )
      return true
    end,
    local_handler = cartographer.handle_vimgrep
  }
end

cartographer.buffers = function(opts)
  local winnr = nvim.nvim_get_current_win()

  local impromptu_opts = {
    title = "🧭 Buffers",
    handler = function(_, ret)
      nvim.nvim_set_current_win(winnr)
      nvim.nvim_command((opts.open_cmd or "b ") .. ret.bufnr)
      return true
    end
  }
  local session = impromptu.filter(impromptu_opts)
  for _, buf in ipairs(vim.api.nvim_call_function("getbufinfo", {})) do
    local name = buf.name
    if name ~= nil then
      session:update{description = name, id = buf.id, bufnr = buf.bufnr}
    end
  end
end

cartographer.dbg = function()
  print(require("inspect")(cache))
end

return cartographer
