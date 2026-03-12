-- gbv.nvim: Git log parsing and graph data construction
local M = {}

local git = require("gbv.git")
local git_exec = git.exec
local uniq = git.uniq

--- Get the root directory of the current repository
---@param start_dir string|nil
---@return string|nil
function M.get_git_root(start_dir)
  local result = git_exec({ "rev-parse", "--show-toplevel" }, start_dir)
  if #result > 0 then
    return result[1]
  end
  return nil
end

--- Get the list of branches containing a commit
---@param repo_root string
---@param hash string
---@return string[]
function M.get_containing_branches(repo_root, hash)
  -- Fetch local and remote branches separately for accurate classification
  local local_lines = git_exec({
    "for-each-ref",
    "--format=%(refname:short)",
    "--contains",
    hash,
    "--",
    "refs/heads",
  }, repo_root)

  local remote_lines = git_exec({
    "for-each-ref",
    "--format=%(refname:short)",
    "--contains",
    hash,
    "--",
    "refs/remotes",
  }, repo_root)

  local local_branches = {}
  local remote_branches = {}
  for _, line in ipairs(local_lines) do
    local_branches[#local_branches + 1] = line
  end
  for _, line in ipairs(remote_lines) do
    if not line:match("/HEAD$") then
      remote_branches[#remote_branches + 1] = line
    end
  end

  table.sort(local_branches)
  table.sort(remote_branches)
  -- 明示的に新テーブルに結合（vim.list_extend は第1引数を破壊的に変更するため）
  local combined = {}
  vim.list_extend(combined, local_branches)
  vim.list_extend(combined, remote_branches)
  return uniq(combined)
end

--- Guess the default branch name
---@param repo_root string
---@return string|nil
function M.get_default_branch(repo_root)
  local remote_head = git_exec({ "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, repo_root)
  if #remote_head > 0 then
    return remote_head[1]:gsub("^origin/", "")
  end

  local local_branches = git_exec({ "for-each-ref", "--format=%(refname:short)", "refs/heads" }, repo_root)
  local branch_set = {}
  for _, branch in ipairs(local_branches) do
    branch_set[branch] = true
  end

  if branch_set.main then
    return "main"
  end
  if branch_set.master then
    return "master"
  end

  local current_branch = git_exec({ "symbolic-ref", "--quiet", "--short", "HEAD" }, repo_root)
  if #current_branch > 0 then
    return current_branch[1]
  end

  return nil
end

--- Get a mapping of HEAD commit hashes to branch names for all branches
---@param repo_root string
---@return table<string, string[]> hash -> branch names
function M.get_branch_map(repo_root)
  local map = {}
  local lines = git_exec({ "branch", "-a", "--format=%(objectname) %(refname:short)" }, repo_root)
  for _, line in ipairs(lines) do
    local hash, name = line:match("^(%S+)%s+(.+)$")
    if hash and name then
      if not map[hash] then
        map[hash] = {}
      end
      table.insert(map[hash], name)
    end
  end
  return map
end

--- Execute git log --graph and return parsed data
---@param repo_root string
---@param limit number|nil
---@return table[] commits list
---@return string[] raw_lines raw graph lines
function M.parse_log(repo_root, limit)
  -- Format: with graph, using separator for easy parsing
  local sep = "\x01"
  local format = table.concat({
    "%H", -- full hash
    "%h", -- abbreviated hash
    "%an", -- author name
    "%ai", -- author date (ISO)
    "%s", -- commit message first line
  }, sep)

  local commit_limit = limit or 200
  local raw = git_exec({
    "log",
    "--all",
    "--graph",
    "--format=" .. format,
    "-" .. tostring(commit_limit),
  }, repo_root)

  local commits = {}
  local graph_lines = {}
  local branch_map = M.get_branch_map(repo_root)

  for _, line in ipairs(raw) do
    local graph_part, data_part = M.split_graph_data(line, sep)
    local entry = {
      graph = graph_part,
      raw_line = line,
    }

    if data_part and data_part ~= "" then
      local parts = vim.split(data_part, sep, { plain = true })
      if #parts >= 5 then
        entry.hash = parts[1]
        entry.short_hash = parts[2]
        entry.author = parts[3]
        entry.date = M.format_date(parts[4])
        entry.message = parts[5]
        entry.branches = branch_map[parts[1]] or {}
        entry.is_commit = true
      end
    else
      entry.is_commit = false
    end

    commits[#commits + 1] = entry
    graph_lines[#graph_lines + 1] = graph_part
  end

  return commits, graph_lines
end

-- 40文字の16進数ハッシュパターン（モジュールレベルでキャッシュ）
local hash_pat = string.rep("%x", 40)

--- Split a line into graph part and data part
---@param line string
---@param sep string
---@return string graph_part
---@return string|nil data_part
function M.split_graph_data(line, sep)
  -- If separator is found, it's a data line
  local sep_pos = line:find(sep, 1, true)
  if sep_pos then
    local before_sep = line:sub(1, sep_pos - 1)
    -- 40文字の16進数フルハッシュを検出
    local hash_start = before_sep:find(hash_pat)
    if hash_start then
      local graph_str = before_sep:sub(1, hash_start - 1)
      local data = before_sep:sub(hash_start) .. line:sub(sep_pos)
      return graph_str, data
    end
    -- If no hash found, treat as graph-only line
    return line, nil
  end
  -- Graph-only line (merge lines, etc.)
  return line, nil
end

--- Format an ISO date string to a shorter form
---@param date_str string
---@return string
function M.format_date(date_str)
  -- "2024-01-15 10:30:00 +0900" -> "2024-01-15 10:30"
  local d = date_str:match("^(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d)")
  return d or date_str:sub(1, 16)
end

--- Get detailed commit information (including diff)
---@param repo_root string
---@param hash string commit hash
---@param default_branch string|nil cached default branch name
---@return table detail
function M.get_commit_detail(repo_root, hash, default_branch)
  local det = {}

  -- Get commit message body
  det.body_lines = git_exec({ "show", "--format=%B", "--no-patch", hash }, repo_root)
  det.contained_branches = M.get_containing_branches(repo_root, hash)
  -- キャッシュ済みの default_branch を使用（未指定時のみ取得）
  det.default_branch = default_branch or M.get_default_branch(repo_root)
  if det.default_branch then
    det.merged_into_default = vim.tbl_contains(det.contained_branches, det.default_branch)
      or vim.tbl_contains(det.contained_branches, "origin/" .. det.default_branch)
  else
    det.merged_into_default = nil
  end

  -- Get changed files list (including root commits, renames)
  local files = git_exec({
    "show",
    "--format=",
    "--name-status",
    "--find-renames",
    "--find-copies",
    "--root",
    hash,
  }, repo_root)
  det.files = {}
  for _, line in ipairs(files) do
    -- Handle status with numbers like R100, C100
    local status_full, paths_str = line:match("^(%a%d*)%s+(.+)$")
    if status_full and paths_str then
      local status = status_full:sub(1, 1) -- "R100" -> "R"
      local path = paths_str
      -- Rename/copy: tab-separated old_path\tnew_path
      if status == "R" or status == "C" then
        local old_path, new_path = paths_str:match("^(.+)\t(.+)$")
        if old_path and new_path then
          path = old_path .. " -> " .. new_path
        end
      end
      det.files[#det.files + 1] = { status = status, path = path }
    end
  end

  -- diff（大量diffによるUIフリーズを防ぐため行数制限あり）
  local MAX_DIFF_LINES = require("gbv").config.max_diff_lines
  local diff = git_exec({
    "show",
    "--format=",
    "--patch",
    "--find-renames",
    "--find-copies",
    "--root",
    hash,
  }, repo_root)
  if #diff > MAX_DIFF_LINES then
    local truncated = vim.list_slice(diff, 1, MAX_DIFF_LINES)
    truncated[#truncated + 1] = ""
    truncated[#truncated + 1] = string.format("... (%d more lines truncated)", #diff - MAX_DIFF_LINES)
    det.diff_lines = truncated
  else
    det.diff_lines = diff
  end

  return det
end

return M
