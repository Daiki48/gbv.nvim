-- gbv.nvim: Main view buffer creation and graph rendering
local M = {}

local graph_mod = require("gbv.graph")
local detail = require("gbv.detail")
local highlight = require("gbv.highlight")

-- Main buffer/window state
M.buf = nil
M.win = nil
M.source_win = nil
M.commits = {}
M.repo_root = nil
M.default_branch = nil
M.page_size = 200
M.commit_limit = M.page_size
M.has_more = false

--- Truncate text based on display width
---@param text string
---@param max_width number
---@return string
local function truncate_text(text, max_width)
  local suffix = ".."
  if vim.fn.strdisplaywidth(text) <= max_width then
    return text
  end

  local limit = max_width - vim.fn.strdisplaywidth(suffix)
  if limit <= 0 then
    return suffix
  end

  -- O(n) cumulative width calculation with table.concat
  local chars = {}
  local w = 0
  local char_count = vim.fn.strchars(text)
  for idx = 0, char_count - 1 do
    local ch = vim.fn.strcharpart(text, idx, 1)
    local cw = vim.fn.strdisplaywidth(ch)
    if w + cw > limit then
      break
    end
    w = w + cw
    chars[#chars + 1] = ch
  end

  return table.concat(chars) .. suffix
end

--- Assign color indices to graph characters
--- Each column (pipe position) gets a color
---@param graph_str string
---@return table[] segments { text, color_index }
local function colorize_graph(graph_str)
  local segments = {}
  local col_index = 0
  local i = 1
  local len = #graph_str

  while i <= len do
    local ch = graph_str:sub(i, i)
    if ch == "|" or ch == "*" then
      col_index = col_index + 1
      segments[#segments + 1] = { text = ch, color = col_index }
      i = i + 1
    elseif ch == "/" or ch == "\\" then
      col_index = col_index + 1
      segments[#segments + 1] = { text = ch, color = col_index }
      i = i + 1
    elseif ch == "_" then
      segments[#segments + 1] = { text = ch, color = math.max(col_index, 1) }
      i = i + 1
    elseif ch == " " then
      segments[#segments + 1] = { text = ch, color = 0 }
      i = i + 1
    else
      segments[#segments + 1] = { text = ch, color = math.max(col_index, 1) }
      i = i + 1
    end
  end

  return segments
end

--- Build a display line
---@param commit table
---@param max_graph_width number
---@return string line display text
---@return table[] hl_segments highlight information
local function build_display_line(commit, max_graph_width)
  if commit.is_more then
    return "[More commits...]", {
      {
        col_start = 0,
        col_end = #"[More commits...]",
        hl = "GbvMore",
      },
    }
  end

  local graph_part = commit.graph or ""
  -- Pad graph part to fixed width
  local padded_graph = graph_part .. string.rep(" ", max_graph_width - vim.fn.strdisplaywidth(graph_part))

  if commit.is_commit then
    -- Branch label
    local branch_str = ""
    if #commit.branches > 0 then
      branch_str = " [" .. table.concat(commit.branches, ", ") .. "]"
    end

    -- コミットメッセージを設定幅で切り詰め
    local msg = commit.message or ""
    local max_msg_width = require("gbv").config.max_message_width
    msg = truncate_text(msg, max_msg_width)

    local line = string.format(
      "%s %s %s %s %s%s",
      padded_graph,
      commit.short_hash,
      commit.date,
      commit.author,
      msg,
      branch_str
    )

    -- Build highlight information
    local hl_segments = {}
    local col = 0

    -- Colorize graph part
    local graph_segs = colorize_graph(graph_part)
    for _, seg in ipairs(graph_segs) do
      if seg.color > 0 then
        hl_segments[#hl_segments + 1] = {
          col_start = col,
          col_end = col + #seg.text,
          hl = highlight.get_graph_hl(seg.color),
        }
      end
      col = col + #seg.text
    end
    -- Skip padding (calculate byte position to match string.format result)
    col = #padded_graph + 1 -- +1 for space

    -- Hash
    local hash_len = #commit.short_hash
    hl_segments[#hl_segments + 1] = { col_start = col, col_end = col + hash_len, hl = "GbvHash" }
    col = col + hash_len + 1

    -- Date
    local date_len = #commit.date
    hl_segments[#hl_segments + 1] = { col_start = col, col_end = col + date_len, hl = "GbvDate" }
    col = col + date_len + 1

    -- Author
    local author_len = #commit.author
    hl_segments[#hl_segments + 1] = { col_start = col, col_end = col + author_len, hl = "GbvAuthor" }
    col = col + author_len + 1

    -- Message
    local msg_byte_len = #msg
    hl_segments[#hl_segments + 1] = { col_start = col, col_end = col + msg_byte_len, hl = "GbvMessage" }
    col = col + msg_byte_len

    -- Branch label
    if branch_str ~= "" then
      hl_segments[#hl_segments + 1] = { col_start = col, col_end = col + #branch_str, hl = "GbvBranchLabel" }
    end

    return line, hl_segments
  else
    -- Non-commit line (merge lines only)
    local hl_segments = {}
    local col = 0
    local graph_segs = colorize_graph(graph_part)
    for _, seg in ipairs(graph_segs) do
      if seg.color > 0 then
        hl_segments[#hl_segments + 1] = {
          col_start = col,
          col_end = col + #seg.text,
          hl = highlight.get_graph_hl(seg.color),
        }
      end
      col = col + #seg.text
    end
    return padded_graph, hl_segments
  end
end

--- Load commits
--- limit+1件を取得し、超過分があればhas_more=trueとする（off-by-one防止）
---@param limit number
---@return table[] commits
---@return boolean has_more
local function load_commits(limit)
  local commits, _ = graph_mod.parse_log(M.repo_root, limit + 1)
  local commit_count = 0
  local result = {}
  for _, commit in ipairs(commits) do
    if commit.is_commit then
      commit_count = commit_count + 1
    end
    -- limit件を超えたら以降は全て除外（余分なグラフ行の混入を防ぐ）
    if commit_count <= limit then
      result[#result + 1] = commit
    end
  end

  return result, commit_count > limit
end

--- Re-render buffer contents
---@param cursor_row number|nil
local function render(cursor_row)
  -- Buffer validity check
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    return false
  end

  local commits, has_more = load_commits(M.commit_limit)

  -- Check if any commit lines exist
  local has_commit = false
  for _, c in ipairs(commits) do
    if c.is_commit then
      has_commit = true
      break
    end
  end

  if not has_commit then
    vim.notify("gbv.nvim: No commits found", vim.log.levels.WARN)
    M.commits = {}
    M.has_more = false
    return false
  end

  if has_more then
    commits[#commits + 1] = {
      is_more = true,
    }
  end

  M.commits = commits
  M.has_more = has_more

  -- Calculate max graph width
  local max_graph_width = 0
  for _, c in ipairs(commits) do
    local w = vim.fn.strdisplaywidth(c.graph or "")
    if w > max_graph_width then
      max_graph_width = w
    end
  end

  -- Build display lines
  local display_lines = {}
  local all_hl_segments = {}
  for i, c in ipairs(commits) do
    local line, hl_segs = build_display_line(c, max_graph_width)
    display_lines[i] = line
    all_hl_segments[i] = hl_segs
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = M.buf })
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, display_lines)

  local ns = vim.api.nvim_create_namespace("gbv_main")
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
  for row, hl_segs in ipairs(all_hl_segments) do
    for _, seg in ipairs(hl_segs) do
      pcall(
        vim.api.nvim_buf_add_highlight,
        M.buf,
        ns,
        seg.hl,
        row - 1,
        seg.col_start,
        seg.col_end
      )
    end
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf })

  if M.win and vim.api.nvim_win_is_valid(M.win) then
    local target_row = cursor_row
    if not target_row or target_row < 1 then
      for i, c in ipairs(commits) do
        if c.is_commit then
          target_row = i
          break
        end
      end
    end
    if target_row then
      local max_row = math.max(#display_lines, 1)
      vim.api.nvim_win_set_cursor(M.win, { math.min(target_row, max_row), 0 })
    end
  end

  return true
end

--- Load more commits
---@param cursor_row number|nil
---@return boolean
function M.load_more(cursor_row)
  if not M.has_more then
    return false
  end

  M.commit_limit = M.commit_limit + M.page_size
  return render(cursor_row)
end

--- Reset internal state
local function reset_state()
  M.buf = nil
  M.win = nil
  M.source_win = nil
  M.commits = {}
  M.repo_root = nil
  M.default_branch = nil
  M.page_size = require("gbv").config.page_size
  M.commit_limit = M.page_size
  M.has_more = false
end

--- Clean up existing GBV resources
local cleaning_up = false
local function cleanup()
  if cleaning_up then
    return
  end
  cleaning_up = true

  detail.close()

  local win = M.win
  local buf = M.buf
  local source_win = M.source_win

  -- Find and close the tab that contains the GBV window
  if win and vim.api.nvim_win_is_valid(win) then
    local gbv_tab = vim.api.nvim_win_get_tabpage(win)
    local tab_count = #vim.api.nvim_list_tabpages()

    if tab_count > 1 then
      -- Restore focus to the source window before closing the tab
      if source_win and vim.api.nvim_win_is_valid(source_win) then
        pcall(vim.api.nvim_set_current_win, source_win)
      end
      -- タブ番号ではなくタブページIDで閉じる（番号ずれリスクを回避）
      local tab_wins = vim.api.nvim_tabpage_list_wins(gbv_tab)
      for _, w in ipairs(tab_wins) do
        pcall(vim.api.nvim_win_close, w, true)
      end
    else
      -- Only one tab remains; delete the buffer and fall back to an empty buffer
      if win and vim.api.nvim_win_is_valid(win) then
        vim.cmd("enew")
      end
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  else
    -- Window is invalid but the buffer still exists; delete it
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  reset_state()
  cleaning_up = false
end

--- Open the main view
function M.open()
  local git_root = graph_mod.get_git_root()
  if not git_root then
    vim.notify("gbv.nvim: Not inside a Git repository", vim.log.levels.ERROR)
    return
  end

  -- Guard against double open: clean up existing GBV if already open
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    cleanup()
  end

  M.repo_root = git_root
  M.default_branch = graph_mod.get_default_branch(git_root)
  M.commit_limit = M.page_size
  M.source_win = vim.api.nvim_get_current_win()

  -- Create buffer
  M.buf = vim.api.nvim_create_buf(false, true)
  -- Use pcall with fallback to avoid duplicate buffer names
  if not pcall(vim.api.nvim_buf_set_name, M.buf, "GBV") then
    vim.api.nvim_buf_set_name(M.buf, "GBV_" .. M.buf)
  end
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = M.buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = M.buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = M.buf })
  vim.api.nvim_set_option_value("filetype", "gbv", { buf = M.buf })

  -- Open a dedicated tab and display the GBV buffer
  vim.cmd("tabnew")
  local empty_buf = vim.api.nvim_get_current_buf()
  M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)
  -- Delete the empty buffer created by tabnew to prevent leaks
  if empty_buf ~= M.buf and vim.api.nvim_buf_is_valid(empty_buf) then
    vim.api.nvim_buf_delete(empty_buf, { force = true })
  end
  vim.api.nvim_set_option_value("number", false, { win = M.win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = M.win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = M.win })
  vim.api.nvim_set_option_value("wrap", false, { win = M.win })
  vim.api.nvim_set_option_value("cursorline", true, { win = M.win })

  if not render() then
    cleanup()
    return
  end

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = M.buf,
    once = true,
    callback = function()
      -- Already handled when called via cleanup(); skip
      if not cleaning_up then
        detail.close()
        reset_state()
      end
    end,
  })

  -- Keymap setup
  local kopts = { noremap = true, silent = true, buffer = M.buf }

  -- Enter: コミット詳細表示 / More読み込み
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local commit = M.commits[row]
    if commit and commit.is_more then
      M.load_more(row)
    elseif commit and commit.is_commit then
      detail.show(commit, M.repo_root, M.win, M.default_branch)
    end
  end, kopts)

  -- q: 閉じる
  vim.keymap.set("n", "q", function()
    cleanup()
  end, kopts)
end

return M
