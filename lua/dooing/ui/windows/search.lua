---------------------------------------------
--- Search feature developed by @derivia
---------------------------------------------

local M = {}

-- Dependencies
local state = require("dooing.state")

-- Local window IDs and buffers
local win_id = nil
local buf_id = nil

-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing_search")

-- Handle search query results
local function handle_search_query(query, main_win_id, render_callback)
	if not query or query == "" then
		if win_id and vim.api.nvim_win_is_valid(win_id) then
			vim.api.nvim_win_close(win_id, true)
			vim.api.nvim_set_current_win(main_win_id)
			win_id = nil
			buf_id = nil
		end
		return
	end

	local done_icon = require("dooing.config").options.formatting.done.icon
	local pending_icon = require("dooing.config").options.formatting.pending.icon

	-- Prepare the search results
	local results = state.search_todos(query)
	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	local lines = { "Search Results for: " .. query, "" }
	local valid_lines = {} -- Store valid todo lines

	if #results > 0 then
		for _, result in ipairs(results) do
			local icon = result.todo.done and done_icon or pending_icon
			local line = string.format("  %s %s", icon, result.todo.text)
			table.insert(lines, line)
			table.insert(valid_lines, { line_index = #lines, result = result })
		end
	else
		table.insert(lines, "  No results found")
		vim.api.nvim_set_current_win(main_win_id)
	end

	-- Add search results to window
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	-- After adding search results, make it unmodifiable
	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)

	-- Highlight todos on search results
	for i, line in ipairs(lines) do
		if line:match("^%s+[" .. done_icon .. pending_icon .. "]") then
			local hl_group = line:match(done_icon) and "DooingDone" or "DooingPending"
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, i - 1, 0, -1)
			for tag in line:gmatch("#(%w+)") do
				local start_idx = line:find("#" .. tag) - 1
				vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Type", i - 1, start_idx, start_idx + #tag + 1)
			end
		elseif line:match("Search Results") then
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "WarningMsg", i - 1, 0, -1)
		end
	end

	-- Set up keymaps for search results
	local keyopts = { buffer = buf_id, nowait = true }

	-- Close search window
	vim.keymap.set("n", "q", function()
		if win_id and vim.api.nvim_win_is_valid(win_id) then
			vim.api.nvim_win_close(win_id, true)
			win_id = nil
			buf_id = nil
			if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
				vim.api.nvim_set_current_win(main_win_id)
			end
		end
	end, keyopts)

	-- Jump to todo in main window
	vim.keymap.set("n", "<CR>", function()
		local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
		local matched_result = nil
		for _, item in ipairs(valid_lines) do
			if item.line_index == current_line then
				matched_result = item.result
				break
			end
		end
		if matched_result then
			vim.api.nvim_win_close(win_id, true)
			win_id = nil
			buf_id = nil
			vim.api.nvim_set_current_win(main_win_id)
			vim.api.nvim_win_set_cursor(main_win_id, { matched_result.lnum + 1, 3 })
		end
	end, keyopts)
end

-- Create and configure search window
function M.create(main_win_id, render_callback)
	-- If search window exists and is valid, focus on it
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_set_current_win(win_id)
		vim.ui.input({ prompt = "Search todos: " }, function(query)
			handle_search_query(query, main_win_id, render_callback)
		end)
		return
	end

	-- If search window exists but is not valid, reset IDs
	if win_id then
		win_id = nil
		buf_id = nil
	end

	-- Create search results buffer
	buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf_id, "buflisted", true)
	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(buf_id, "filetype", "todo_search")

	-- Configure window dimensions
	local width = 40
	local height = 10
	local ui = vim.api.nvim_list_uis()[1]
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)

	-- Create window
	win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Search Todos ",
		title_pos = "center",
	})

	-- Create search query pane
	vim.ui.input({ prompt = "Search todos: " }, function(query)
		handle_search_query(query, main_win_id, render_callback)
	end)

	-- Close the search window if main window is closed
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(main_win_id),
		callback = function()
			if win_id and vim.api.nvim_win_is_valid(win_id) then
				vim.api.nvim_win_close(win_id, true)
				win_id = nil
				buf_id = nil
			end
		end,
	})
end

-- Get window and buffer IDs
function M.get_ids()
	return {
		win_id = win_id,
		buf_id = buf_id,
	}
end

-- Check if window is valid
function M.is_valid()
	return win_id and vim.api.nvim_win_is_valid(win_id)
end

-- Close window
function M.close()
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
		win_id = nil
		buf_id = nil
	end
end

return M
