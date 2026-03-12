-- gbv.nvim: Shared git utilities
local M = {}

--- Execute a git command and return the result
---@param args string[]
---@param repo_root string|nil
---@return string[]
function M.exec(args, repo_root)
  local cmd = { "git" }
  if repo_root and repo_root ~= "" then
    cmd[#cmd + 1] = "-C"
    cmd[#cmd + 1] = repo_root
  end
  for _, a in ipairs(args) do
    cmd[#cmd + 1] = a
  end
  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("gbv.nvim: git command failed: " .. table.concat(cmd, " "), vim.log.levels.WARN)
    return {}
  end
  return result
end

--- Return a deduplicated array
---@param items string[]
---@return string[]
function M.uniq(items)
  local seen = {}
  local result = {}
  for _, item in ipairs(items) do
    if item ~= "" and not seen[item] then
      seen[item] = true
      result[#result + 1] = item
    end
  end
  return result
end

return M
