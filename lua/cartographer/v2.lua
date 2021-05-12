-- luacheck: globals vim
-- [[ Version 2 of cartographer
--
-- This tries to reuse a lot of stuff and centralize the complexity
-- operations are now defined as data ]]
local util = require("cartographer.util")
local cache = require("cartographer.cache")
local config = require("cartographer.config")
local low_level = require("cartographer.internal")
local fts = require("cartographer.fts")
local classifier = require("classifier")

local dir_handler = function(handler)
  return function(opt, session, selected)
    if selected == "__up_dir" or selected.action == "__up_dir" then
      session.hls = {}
      vim.fn.chanclose(cache[session.cartographer_ui_id].job)
      opt.path = util.dir_up(opt.path)
      return opt
    else
      return handler(opt, session, selected)
    end
  end
end

local open_file = function(opt, _, ret)
  vim.api.nvim_set_current_win(opt.winnr)
  if ret.self_handler ~= nil then
    return ret.self_handler()
  else
    local command = (opt.open_cmd or "edit") .. " "
    if ret.ln ~= nil then
      command = command .. "+" .. ret.ln .. " "
    end
    command = command .. opt.path .. "/" .. ret.path
    vim.api.nvim_command(command)
  end
  return true
end

local tchd = function(opt, _, ret)
  vim.api.nvim_command("tcd " .. opt.path .. "/" .. ret.description)
  return true
end


local traits = {
  dir = {
    defaults = {
      mappings = {['<C-h>'] = "__up_dir"}
    },
    middleware = dir_handler
  },
  git = {
  context_middleware = function(context)
    return util.merge(
      (context ~= nil and context() or {}), {
        path = vim.trim(vim.fn.system("git rev-parse --show-toplevel"))
      })
  end
  }
}

local apply_trait = function(opt, trait)
  opt.defaults = util.merge(opt.defaults, trait.defaults)
  util.update(opt, "handler", trait.middleware)
  util.update(opt, "context", trait.context_middleware)
  return opt
end

local v2 = {}

local define = function(opt)
  v2[opt.name] = function()

    return setmetatable({}, {
        __index = function(this, flag)
        rawset(this, flag, opt.flags[flag])
        return this
        end,
        __call = function(flags, cfg)
          local payload

          payload = util.merge(
            -- Primitive values
            {
              _type = "job",
              path = vim.fn.getcwd(),
              winnr = vim.api.nvim_get_current_win(),
              buf = vim.api.nvim_get_current_buf(),
              local_handler = low_level.handle,
              prepare = function(obj)
                return obj.search_command
              end
            },
            -- Default, static values
            opt.defaults,
            -- Globally configured values
            config.data[opt.name],
            -- Flags
            flags,
            -- Structural arguments
            {
              title = opt.name,
              handler = function(session, selected)
                local ret = opt.handler(payload, session, selected)
                if type(ret) == "table" then
                  low_level.create_filter(ret, session)
                else
                  return ret or true
                end
              end,
            },
            -- Dynamic values
            (opt.context ~= nil and opt.context() or {}),
            -- User-provided arguments
            cfg)

          util.update(payload, "path", vim.fn.expand)

          return low_level.create_filter(payload)
        end
      })
  end
end

local function metadef (closure)
  return setmetatable({}, {
    __index = function(this, key)
      return metadef(function(opt)
        return this(apply_trait(opt, traits[key]))
      end)
    end,
    __call = function(_, opt)
      return closure(opt)
    end
})
end

local def = metadef(define)

-- Actual operations

def.dir{
  name = "project",
  flags = {
    reopen = function(opt)
      return opt.root
    end
  },
  defaults = {
    path = "$HOME/code",
    search_command = "find -type d -name '.git' -maxdepth 3 -printf '%h\\n'",
  },
  handler = tchd
}

def.dir{
  name = "files",
  flags = {
    reopen = function(opt)
      return opt.root
    end
  },
  defaults = {
    search_command = "find -type f",
  },
  handler = open_file
}

def.git{
  name = "dirty",
  defaults = {
    search_command = "git status --porcelain | awk '{print $NF}'"
  },
  handler = open_file
}

def.git{
  name = "checkout",
  defaults = {
    search_command = "git branch"
  },
  handler = function(_, _, selected)
    vim.fn.system("git checkout " .. selected.description)
  end
}

def{
  name = "todo",
  defaults = {
    local_handler = low_level.handle_vimgrep,
    search_command = "find . -not -path '*/\\.*' -type f | xargs grep -nHE '(TODO|HACK|FIXME)'"
  },
  handler = open_file
}

def.dir{
  name = "cd",
  defaults = {
    custom = {
      {description = "."},
      {description = "..", action = "__up_dir"}
    },
    search_command = "find -type d -not -path './.git/*' -not -name '\\.*'"
  },
  handler = tchd
}

def{
  name = "buffers",
  defaults = {
    _type = "static",
    custom = function()
      local buffers = vim.fn.getbufinfo()
      return util.map(buffers, function(buf)
        local name = buf.name
        if name ~= nil then
          return {description = name, id = buf.id, bufnr = buf.bufnr}
        end
      end)
    end
  },
  handler = function(opt, _, ret)
    vim.api.nvim_set_current_win(opt.winnr)
    vim.api.nvim_command((opt.open_cmd or "b ") .. ret.bufnr)
    return true
  end
}

def{
  name = "functions",
  defaults = {
    local_handler = low_level.handle_vimgrep,
    search_command = "rg --vimgrep",
    prepare = function(obj)
      local ft = vim.api.nvim_buf_get_option(obj.buf, "ft")
      if ft == nil then
        return
      end
      local fn_query = fts[ft].functions
      if fn_query ~= nil then
        return obj.search_command .. " -g '*.{" .. table.concat(classifier.fts(ft), ",") .."}' '" .. fn_query .. "'"
      end
    end,
  },
  handler = open_file
}

return setmetatable({}, {__index = function(_, k) return rawget(v2, k)() end })
