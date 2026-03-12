-- gbv.nvim: リリースフロー DAG データ構築
local M = {}

local git = require("gbv.git")

---@class FlowTag
---@field name string        -- "v1.0"
---@field hash string        -- コミットハッシュ（annotated なら deref 済み）
---@field date string        -- "2024-01-15"

---@class FlowBranch
---@field name string        -- "release1"
---@field head_hash string

---@class FlowDAG
---@field main_branch string
---@field tags FlowTag[]               -- 日付降順
---@field branches FlowBranch[]
---@field matrix table<string, table<string, boolean>>
---@field branch_birth table<string, string|nil> -- branch_name -> 最古のタグ日付（存在判定用）

--- タグ一覧を日付降順で取得
---@param repo_root string
---@param tag_pattern string|nil  -- Lua パターン（nil なら全タグ）
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
      -- annotated tag なら deref したハッシュを使用、なければ tag 自体のハッシュ
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

--- リリースブランチ一覧を取得
---@param repo_root string
---@param pattern string  -- Lua パターン（例: "^release"）
---@param main_branch string|nil  -- メインブランチ名（先頭に配置する）
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

  -- メインブランチを先頭に配置
  if main_entry then
    table.insert(branches, 1, main_entry)
  end

  return branches
end

--- マージマトリクスを構築
--- matrix[tag_name][branch_name] = true（マージ済み）/ false（未マージ）
--- ブランチ数回の git コマンドで済む（タグ数回より効率的）
---@param repo_root string
---@param tags FlowTag[]
---@param branches FlowBranch[]
---@return table<string, table<string, boolean>>
function M.build_merge_matrix(repo_root, tags, branches)
  -- タグ名のセットを用意
  local tag_set = {}
  for _, tag in ipairs(tags) do
    tag_set[tag.name] = true
  end

  -- 初期化: 全セルを false に
  local matrix = {}
  for _, tag in ipairs(tags) do
    matrix[tag.name] = {}
    for _, b in ipairs(branches) do
      matrix[tag.name][b.name] = false
    end
  end

  -- ブランチごとに git tag --merged を実行（ブランチ数回で済む）
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

--- ブランチの誕生タイミングを推定（メインブランチからの分岐日）
--- main..branch の差分ログから最古コミットの日付を取得する。
--- 差分がない場合（= main 自体など）は nil を返す（常に existed=true 扱い）。
---@param repo_root string
---@param branches FlowBranch[]
---@param main_branch string
---@return table<string, string|nil> branch_name -> 分岐後の最古コミット日付
function M.get_branch_birth_dates(repo_root, branches, main_branch)
  local birth = {}
  for _, b in ipairs(branches) do
    if b.name == main_branch then
      -- メインブランチ自体は常に存在扱い
      birth[b.name] = nil
    else
      -- main..branch でメインブランチとの差分コミットを取得
      local lines = git.exec({
        "log",
        "--format=%ai",
        "--reverse",
        main_branch .. ".." .. b.name,
      }, repo_root)
      if #lines > 0 then
        birth[b.name] = lines[1]:match("^(%d%d%d%d%-%d%d%-%d%d)") or nil
      else
        -- 差分なし（main と同一）→ 常に existed=true
        birth[b.name] = nil
      end
    end
  end
  return birth
end

--- DAG 全体を構築
---@param repo_root string
---@param config table  -- { release_branch_pattern, main_branch, tag_pattern }
---@return FlowDAG|nil
---@return string|nil error_message
function M.build_dag(repo_root, config)
  local graph = require("gbv.graph")
  local main_branch = config.main_branch or graph.get_default_branch(repo_root)
  if not main_branch then
    return nil, "メインブランチを検出できませんでした"
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
