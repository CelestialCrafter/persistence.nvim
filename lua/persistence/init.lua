local Config = require("persistence.config")

local uv = vim.uv or vim.loop

local M = {}
M._active = false

local e = vim.fn.fnameescape

---@param opts? {branch?: boolean}
function M.current()
  local name = Config.options.name()
  if name == nil then
    return nil
  end

  return Config.options.dir .. name .. ".vim"
end

function M.setup(opts)
  Config.setup(opts)
  M.start()
end

function M.fire(event)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "Persistence" .. event,
  })
end

-- Check if a session is active
function M.active()
  return M._active
end

function M.start()
  M._active = true
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("persistence", { clear = true }),
    callback = function()
      M.fire("SavePre")

      if Config.options.need > 0 then
        local bufs = vim.tbl_filter(function(b)
          if vim.bo[b].buftype ~= "" or vim.bo[b].filetype == "gitcommit" or vim.bo[b].filetype == "gitrebase" then
            return false
          end
          return vim.api.nvim_buf_get_name(b) ~= ""
        end, vim.api.nvim_list_bufs())
        if #bufs < Config.options.need then
          return
        end
      end

      M.save()
      M.fire("SavePost")
    end,
  })
end

function M.stop()
  M._active = false
  pcall(vim.api.nvim_del_augroup_by_name, "persistence")
end

function M.save()
  local path = M.current()
  if path == nil then
    return
  end
  
  vim.cmd("mks! " .. e(path))
end

---@param opts? { last?: boolean }
function M.load(opts)
  opts = opts or {}
  ---@type string
  local file
  if opts.last then
    file = M.last()
  else
      file = M.current()
  end

  if file and vim.fn.filereadable(file) ~= 0 then
    M.fire("LoadPre")
    vim.cmd("silent! source " .. e(file))
    M.fire("LoadPost")
  end
end

---@return string[]
function M.list()
  local sessions = vim.fn.glob(Config.options.dir .. "*.vim", true, true)
  table.sort(sessions, function(a, b)
    return uv.fs_stat(a).mtime.sec > uv.fs_stat(b).mtime.sec
  end)
  return sessions
end

function M.last()
  return M.list()[1]
end

function M.select()
  ---@type { session: string, file: string }[]
  local items = {}
  local have = {} ---@type table<string, boolean>
  for _, session in ipairs(M.list()) do
    if uv.fs_stat(session) then
      local file = session:sub(#Config.options.dir + 1, -5)
      items[#items + 1] = { session = session, file = file }
    end
  end
  vim.ui.select(items, {
    prompt = "Select a session: ",
    format_item = function(item)
      return vim.fn.fnamemodify(item.dir, ":p:~")
    end,
  }, function(item)
    if item then
      vim.fn.chdir(item.dir)
      M.load()
    end
  end)
end

return M
