-- gbv.nvim: Release flow DAG data construction
local M = {}

local git = require("gbv.git")

---@class FlowTag
---@field name string        -- "v1.0"
---@field hash string        -- commit hash (dereferenced for annotated tags)
---@field date string        -- "2024-01-15"

---@class FlowBranch
---@field name string        -- "release1"
---@field head_hash string

---@class FlowDAG
---@field main_branch string
---@field tags FlowTag[]               -- sorted by date descending
---@field branches FlowBranch[]
---@field matrix table<string, table<string, boolean>>
---@field branch_birth table<string, string|nil> -- branch_name -> earliest commit date (for existence check)

--- Get tags sorted by date descending
---@param repo_root string
---@param tag_pattern string|nil  -- Lua pattern (nil = all tags)
---@return FlowTag[]
function M.get_tags(repo_root, tag_pattern)
  local sep = "\x01"
  local lines = git.exec({
    "tag",
    "--sort=-creatordate",
    "--format=%(refname:short)" .. sep .. "%(objectname)" .. sep .. "%(*objectname)" .. sep .. "%(creatordate:iso)",
  }, repo_root)

  local tags = {}
  for _, line in ipairs(lines) do
    local parts = vim.split(line, sep, { plain = true })
    if #parts >= 4 then
      local name = parts[1]
      -- Use dereferenced hash for annotated tags, otherwise the tag's own hash
      local hash = (parts[3] ~= "" and parts[3]) or parts[2]
      local date = parts[4]:match("^(%d%d%d%d%-%d%d%-%d%d)") or parts[4]:sub(1, 10)

      local pattern_ok, pattern_match = true, true
      if tag_pattern then
        pattern_ok, pattern_match = pcall(string.match, name, tag_pattern)
      end
      if pattern_ok and pattern_match then
        tags[#tags + 1] = {
          name = name,
          hash = hash,
          date = date,
        }
      end
    end
  end

  return tags
end

--- Get release branches
---@param repo_root string
---@param pattern string  -- Lua pattern (e.g. "^release")
---@param main_branch string|nil  -- main branch name (placed first)
---@return FlowBranch[]
function M.get_release_branches(repo_root, pattern, main_branch)
  local sep = "\x01"
  local lines = git.exec({
    "for-each-ref",
    "--format=%(refname:short)" .. sep .. "%(objectname:short)",
    "refs/heads/",
  }, repo_root)

  local branches = {}
  local main_entry = nil

  for _, line in ipairs(lines) do
    local parts = vim.split(line, sep, { plain = true })
    if #parts >= 2 then
      local name = parts[1]
      local head_hash = parts[2]

      if main_branch and name == main_branch then
        main_entry = { name = name, head_hash = head_hash }
      else
        local ok, match = pcall(string.match, name, pattern)
        if ok and match then
          branches[#branches + 1] = { name = name, head_hash = head_hash }
        end
      end
    end
  end

  -- Place main branch first
  if main_entry then
    table.insert(branches, 1, main_entry)
  end

  return branches
end

--- Build merge matrix
--- matrix[tag_name][branch_name] = true (merged) / false (not merged)
--- Runs one git command per branch (more efficient than per-tag)
---@param repo_root string
---@param tags FlowTag[]
---@param branches FlowBranch[]
---@return table<string, table<string, boolean>>
function M.build_merge_matrix(repo_root, tags, branches)
  -- Build tag name set
  local tag_set = {}
  for _, tag in ipairs(tags) do
    tag_set[tag.name] = true
  end

  -- Initialize all cells to false
  local matrix = {}
  for _, tag in ipairs(tags) do
    matrix[tag.name] = {}
    for _, b in ipairs(branches) do
      matrix[tag.name][b.name] = false
    end
  end

  -- Run git tag --merged per branch (branch-count commands total)
  for _, b in ipairs(branches) do
    local merged_tags = git.exec({
      "tag",
      "--merged",
      b.name,
    }, repo_root)
    for _, tag_name in ipairs(merged_tags) do
      if tag_name ~= "" and tag_set[tag_name] and matrix[tag_name] then
        matrix[tag_name][b.name] = true
      end
    end
  end

  return matrix
end

--- Estimate branch birth date (fork point from main branch)
--- Uses main..branch diff log to get the earliest commit date.
--- Returns nil if no diff (e.g. main itself), meaning always existed.
---@param repo_root string
---@param branches FlowBranch[]
---@param main_branch string
---@return table<string, string|nil> branch_name -> earliest commit date after fork
function M.get_branch_birth_dates(repo_root, branches, main_branch)
  local birth = {}
  for _, b in ipairs(branches) do
    if b.name == main_branch then
      -- Main branch always existed
      birth[b.name] = nil
    else
      -- Get commits unique to this branch (not in main)
      local lines = git.exec({
        "log",
        "--format=%ai",
        "--reverse",
        main_branch .. ".." .. b.name,
      }, repo_root)
      if #lines > 0 then
        birth[b.name] = lines[1]:match("^(%d%d%d%d%-%d%d%-%d%d)") or nil
      else
        -- No diff (identical to main) -> always existed
        birth[b.name] = nil
      end
    end
  end
  return birth
end

--- Build the full DAG
---@param repo_root string
---@param config table  -- { release_branch_pattern, main_branch, tag_pattern }
---@return FlowDAG|nil
---@return string|nil error_message
function M.build_dag(repo_root, config)
  local graph = require("gbv.graph")
  local main_branch = config.main_branch or graph.get_default_branch(repo_root)
  if not main_branch then
    return nil, "Could not detect main branch"
  end

  local tags = M.get_tags(repo_root, config.tag_pattern)
  if #tags == 0 then
    return nil, "No tags found"
  end

  local branches = M.get_release_branches(repo_root, config.release_branch_pattern, main_branch)
  if #branches == 0 then
    return nil, "No release branches matching pattern: " .. config.release_branch_pattern
  end

  local matrix = M.build_merge_matrix(repo_root, tags, branches)
  local branch_birth = M.get_branch_birth_dates(repo_root, branches, main_branch)

  return {
    main_branch = main_branch,
    tags = tags,
    branches = branches,
    matrix = matrix,
    branch_birth = branch_birth,
  }
end

return M
