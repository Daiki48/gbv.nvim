-- gbv.nvim: フロービュー UI（バッファ、レンダリング、ヘッダー固定、キーマップ）
local M = {}

local flow = require("gbv.flow")
local detail_mod = require("gbv.detail")
local graph_mod = require("gbv.graph")

-- Namespace（モジュールレベルでキャッシュ）
local ns_header = vim.api.nvim_create_namespace("gbv_flow_header")
local ns_data = vim.api.nvim_create_namespace("gbv_flow_data")

-- UI state
M.header_buf = nil
M.header_win = nil
M.data_buf = nil
M.data_win = nil
M.source_win = nil
M.repo_root = nil
M.dag = nil

--- ヘッダーウィンドウとデータウィンドウを含むタブ全体を閉じる
local cleaning_up = false
local function cleanup()
  if cleaning_up then
    return
  end
  cleaning_up = true

  detail_mod.close()
  pcall(vim.api.nvim_del_augroup_by_name, "GbvFlowWinEnter")

  local source_win = M.source_win
  local header_win = M.header_win
  local data_win = M.data_win
  local header_buf = M.header_buf
  local data_buf = M.data_buf

  -- タブを特定して閉じる
  local tab_win = data_win or header_win
  if tab_win and vim.api.nvim_win_is_valid(tab_win) then
    local gbv_tab = vim.api.nvim_win_get_tabpage(tab_win)
    local tab_count = #vim.api.nvim_list_tabpages()

    if tab_count > 1 then
      if source_win and vim.api.nvim_win_is_valid(source_win) then
        pcall(vim.api.nvim_set_current_win, source_win)
      end
      local tab_wins = vim.api.nvim_tabpage_list_wins(gbv_tab)
      for _, w in ipairs(tab_wins) do
        pcall(vim.api.nvim_win_close, w, true)
      end
    else
      -- タブが1つしかない場合
      if data_win and vim.api.nvim_win_is_valid(data_win) then
        vim.api.nvim_set_current_win(data_win)
        vim.cmd("enew")
      end
      if header_win and vim.api.nvim_win_is_valid(header_win) then
        pcall(vim.api.nvim_win_close, header_win, true)
      end
      if header_buf and vim.api.nvim_buf_is_valid(header_buf) then
        vim.api.nvim_buf_delete(header_buf, { force = true })
      end
      if data_buf and vim.api.nvim_buf_is_valid(data_buf) then
        vim.api.nvim_buf_delete(data_buf, { force = true })
      end
    end
  else
    -- ウィンドウ無効だがバッファが残っている場合
    if header_buf and vim.api.nvim_buf_is_valid(header_buf) then
      vim.api.nvim_buf_delete(header_buf, { force = true })
    end
    if data_buf and vim.api.nvim_buf_is_valid(data_buf) then
      vim.api.nvim_buf_delete(data_buf, { force = true })
    end
  end

  M.header_buf = nil
  M.header_win = nil
  M.data_buf = nil
  M.data_win = nil
  M.source_win = nil
  M.repo_root = nil
  M.dag = nil
  cleaning_up = false
end

--- マーカー文字を返す
---@param merged boolean
---@param branch_existed boolean
---@return string marker
---@return string hl_group
local function get_marker(merged, branch_existed)
  if not branch_existed then
    return "─", "GbvFlowLine"
  elseif merged then
    return "●", "GbvFlowMerged"
  else
    return "○", "GbvFlowNotMerged"
  end
end

--- HEAD 行のマーカーを返す
---@return string
---@return string
local function get_head_marker()
  return "◎", "GbvFlowHead"
end

--- 文字列を指定幅にパディング（表示幅ベース）
---@param text string
---@param width number
---@return string
local function pad_right(text, width)
  local display_width = vim.fn.strdisplaywidth(text)
  if display_width >= width then
    return text
  end
  return text .. string.rep(" ", width - display_width)
end

--- レンダリング: ヘッダーバッファとデータバッファに内容を書き込む
---@param dag FlowDAG
local function render(dag)
  local branches = dag.branches
  local tags = dag.tags
  local matrix = dag.matrix
  local branch_birth = dag.branch_birth

  -- 列幅計算
  local tag_col_width = 0
  for _, tag in ipairs(tags) do
    local w = vim.fn.strdisplaywidth(tag.name) + 2 + 10 + 2 -- name + "  " + date + "  "
    if w > tag_col_width then
      tag_col_width = w
    end
  end
  -- 最低幅確保
  tag_col_width = math.max(tag_col_width, 20)

  local branch_col_width = 0
  for _, b in ipairs(branches) do
    local w = vim.fn.strdisplaywidth(b.name)
    if w > branch_col_width then
      branch_col_width = w
    end
  end
  branch_col_width = math.max(branch_col_width + 2, 8) -- 最低 8 文字

  -- ━━━ ヘッダーバッファ ━━━
  local header_lines = {}
  local header_hl = {}

  -- ブランチ名ヘッダー行
  local branch_header = pad_right("", tag_col_width)
  local branch_hl_marks = {}
  for _, b in ipairs(branches) do
    local col_start = #branch_header
    local padded = pad_right(b.name, branch_col_width)
    branch_header = branch_header .. padded
    branch_hl_marks[#branch_hl_marks + 1] = {
      col_start = col_start,
      col_end = col_start + #b.name,
      hl = "GbvFlowBranch",
    }
  end
  header_lines[1] = branch_header
  header_hl[1] = branch_hl_marks

  -- 罫線行
  local separator = string.rep("━", vim.fn.strdisplaywidth(branch_header))
  header_lines[2] = separator
  header_hl[2] = { { col_start = 0, col_end = #separator, hl = "GbvFlowLine" } }

  vim.api.nvim_set_option_value("modifiable", true, { buf = M.header_buf })
  vim.api.nvim_buf_set_lines(M.header_buf, 0, -1, false, header_lines)
  vim.api.nvim_buf_clear_namespace(M.header_buf, ns_header, 0, -1)
  for row, marks in ipairs(header_hl) do
    for _, mark in ipairs(marks) do
      pcall(vim.api.nvim_buf_add_highlight, M.header_buf, ns_header, mark.hl, row - 1, mark.col_start, mark.col_end)
    end
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.header_buf })

  -- ━━━ データバッファ ━━━
  local data_lines = {}
  local data_hl = {}

  -- タグ行（日付降順 = 最新が上）
  for _, tag in ipairs(tags) do
    local tag_label = tag.name .. "  " .. tag.date
    local line = pad_right(tag_label, tag_col_width)
    local line_hl = {}

    -- タグ名ハイライト
    line_hl[#line_hl + 1] = {
      col_start = 0,
      col_end = #tag.name,
      hl = "GbvFlowTag",
    }
    -- 日付ハイライト
    local date_start = #tag.name + 2
    line_hl[#line_hl + 1] = {
      col_start = date_start,
      col_end = date_start + #tag.date,
      hl = "GbvDate",
    }

    -- 各ブランチ列のマーカー
    for _, b in ipairs(branches) do
      local merged = matrix[tag.name] and matrix[tag.name][b.name]
      -- ブランチが存在していたか判定（ブランチの最初のコミット日 <= タグ日付）
      local birth = branch_birth[b.name]
      local existed = true
      if birth and tag.date < birth then
        existed = false
      end

      local marker, hl_group = get_marker(merged, existed)
      local col_start = #line
      local padded = pad_right(marker, branch_col_width)
      line = line .. padded
      line_hl[#line_hl + 1] = {
        col_start = col_start,
        col_end = col_start + #marker,
        hl = hl_group,
      }
    end

    data_lines[#data_lines + 1] = line
    data_hl[#data_hl + 1] = line_hl
  end

  -- 罫線
  local data_sep = string.rep("━", vim.fn.strdisplaywidth(branch_header))
  data_lines[#data_lines + 1] = data_sep
  data_hl[#data_hl + 1] = { { col_start = 0, col_end = #data_sep, hl = "GbvFlowLine" } }

  -- HEAD 行
  local head_line = pad_right("HEAD", tag_col_width)
  local head_hl = {}
  head_hl[#head_hl + 1] = { col_start = 0, col_end = 4, hl = "GbvFlowHeader" }
  for _, b in ipairs(branches) do
    local marker, hl_group = get_head_marker()
    local col_start = #head_line
    local padded = pad_right(marker, branch_col_width)
    head_line = head_line .. padded
    head_hl[#head_hl + 1] = {
      col_start = col_start,
      col_end = col_start + #marker,
      hl = hl_group,
    }
    -- ブランチの HEAD ハッシュも表示したい場合は別途追加可能
    _ = b -- suppress unused warning
  end
  data_lines[#data_lines + 1] = head_line
  data_hl[#data_hl + 1] = head_hl

  vim.api.nvim_set_option_value("modifiable", true, { buf = M.data_buf })
  vim.api.nvim_buf_set_lines(M.data_buf, 0, -1, false, data_lines)
  vim.api.nvim_buf_clear_namespace(M.data_buf, ns_data, 0, -1)
  for row, marks in ipairs(data_hl) do
    for _, mark in ipairs(marks) do
      pcall(vim.api.nvim_buf_add_highlight, M.data_buf, ns_data, mark.hl, row - 1, mark.col_start, mark.col_end)
    end
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.data_buf })

  -- カーソルを最初のタグ行に
  if M.data_win and vim.api.nvim_win_is_valid(M.data_win) then
    vim.api.nvim_win_set_cursor(M.data_win, { 1, 0 })
  end
end

--- スクラッチバッファを作成
---@param name string
---@return number buf
local function create_scratch_buf(name)
  local buf = vim.api.nvim_create_buf(false, true)
  if not pcall(vim.api.nvim_buf_set_name, buf, name) then
    vim.api.nvim_buf_set_name(buf, name .. "_" .. buf)
  end
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  return buf
end

--- ウィンドウの共通オプション設定
---@param win number
local function set_win_options(win)
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
end

--- フロービューを開く
function M.open()
  local git_root = graph_mod.get_git_root()
  if not git_root then
    vim.notify("gbv.nvim: Not inside a Git repository", vim.log.levels.ERROR)
    return
  end

  -- 二重オープンガード（ヘッダーまたはデータバッファが残存している場合）
  if
    (M.data_buf and vim.api.nvim_buf_is_valid(M.data_buf))
    or (M.header_buf and vim.api.nvim_buf_is_valid(M.header_buf))
  then
    cleanup()
  end

  M.repo_root = git_root
  M.source_win = vim.api.nvim_get_current_win()

  -- DAG 構築
  local config = require("gbv").config.flow
  local dag, err = flow.build_dag(git_root, config)
  if not dag then
    vim.notify("gbv.nvim: " .. (err or "Unknown error"), vim.log.levels.WARN)
    return
  end
  M.dag = dag

  -- バッファ作成
  M.header_buf = create_scratch_buf("GBVFlow-Header")
  vim.api.nvim_set_option_value("filetype", "gbv-flow", { buf = M.header_buf })
  M.data_buf = create_scratch_buf("GBVFlow-Data")
  vim.api.nvim_set_option_value("filetype", "gbv-flow", { buf = M.data_buf })

  -- 専用タブを開く
  vim.cmd("tabnew")
  local empty_buf = vim.api.nvim_get_current_buf()

  -- ヘッダーウィンドウ（上部固定 2行）
  M.header_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.header_win, M.header_buf)
  set_win_options(M.header_win)
  vim.api.nvim_set_option_value("winfixheight", true, { win = M.header_win })
  vim.api.nvim_win_set_height(M.header_win, 2)

  -- データウィンドウ（下部スクロール可能）
  vim.cmd("belowright split")
  M.data_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.data_win, M.data_buf)
  set_win_options(M.data_win)
  vim.api.nvim_set_option_value("cursorline", true, { win = M.data_win })

  -- tabnew で作られた空バッファを削除
  if empty_buf ~= M.header_buf and empty_buf ~= M.data_buf and vim.api.nvim_buf_is_valid(empty_buf) then
    vim.api.nvim_buf_delete(empty_buf, { force = true })
  end

  -- レンダリング
  render(dag)

  -- ヘッダーウィンドウへのカーソル移動を防止（フォーカスをデータウィンドウに固定）
  local augroup = vim.api.nvim_create_augroup("GbvFlowWinEnter", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    callback = function()
      if M.header_win and vim.api.nvim_get_current_win() == M.header_win then
        if M.data_win and vim.api.nvim_win_is_valid(M.data_win) then
          vim.api.nvim_set_current_win(M.data_win)
        end
      end
    end,
  })

  -- BufWipeout でクリーンアップ
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = M.data_buf,
    once = true,
    callback = function()
      if not cleaning_up then
        detail_mod.close()
        pcall(vim.api.nvim_del_augroup_by_name, "GbvFlowWinEnter")
        M.header_buf = nil
        M.header_win = nil
        M.data_buf = nil
        M.data_win = nil
        M.source_win = nil
        M.repo_root = nil
        M.dag = nil
      end
    end,
  })

  -- ━━━ キーマップ設定 ━━━
  local kopts = { noremap = true, silent = true, buffer = M.data_buf }

  -- q: 閉じる
  vim.keymap.set("n", "q", function()
    cleanup()
  end, kopts)

  -- Enter: タグ行 → 詳細表示
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local tag = dag.tags[row]
    if tag then
      -- タグのコミット詳細を表示（tag.hash はフルハッシュ）
      local commit = {
        is_commit = true,
        hash = tag.hash,
        short_hash = tag.hash:sub(1, 7),
        author = "",
        date = tag.date,
        message = tag.name,
        branches = {},
      }
      detail_mod.show(commit, M.repo_root, M.data_win, dag.main_branch)
    end
  end, kopts)

  -- r: リフレッシュ
  vim.keymap.set("n", "r", function()
    local new_dag, new_err = flow.build_dag(M.repo_root, require("gbv").config.flow)
    if not new_dag then
      vim.notify("gbv.nvim: " .. (new_err or "Unknown error"), vim.log.levels.WARN)
      return
    end
    M.dag = new_dag
    render(new_dag)
  end, kopts)
end

return M
