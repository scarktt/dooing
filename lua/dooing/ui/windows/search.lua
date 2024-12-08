---------------------------------------------
--- Search feature developed by @derivia
---------------------------------------------

local M = {}

-- Dependencies
local state = require("dooing.state")
local config = require("dooing.config")
local Render = require("dooing.ui.render")

-- Local window IDs and buffers
local win_id = nil
local buf_id = nil

-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing_search")

-- Simplified formatting configuration for search results
local search_formatting = {
	pending = {
		icon = "○",
		format = { "icon", "text" }, -- Simplified format for search results
	},
	done = {
		icon = "✓",
		format = { "icon", "text" }, -- Simplified format for search results
	},
}

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

	-- Prepare the search results
	local results = state.search_todos(query)
	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	local lines = {
		"Search Results for: " .. query,
		"",
	}
	local valid_lines = {}

	if #results > 0 then
		for _, result in ipairs(results) do
			-- Use the render module's format_todo with simplified formatting
			local todo_text = Render.format_todo(result.todo, search_formatting)
			table.insert(lines, "  " .. todo_text)
			table.insert(valid_lines, { line_index = #lines, result = result })
		end
	else
		table.insert(lines, "  No results found")
		vim.api.nvim_set_current_win(main_win_id)
	end

	-- Add search results to window
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

	-- Apply highlights
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon

	for i, line in ipairs(lines) do
		local line_nr = i - 1
		if line:match("^%s+[" .. done_icon .. pending_icon .. "]") then
			for _, valid_line in ipairs(valid_lines) do
				if valid_line.line_index == i then
					local todo = valid_line.result.todo
					-- Apply base highlight based on todo status
					if todo.done then
						vim.api.nvim_buf_add_highlight(buf_id, ns_id, "DooingDone", line_nr, 0, -1)
					else
						-- Get priority-based highlight if todo has priorities
						local score = state.get_priority_score(todo)
						local hl_group = "DooingPending"

						if todo.priorities and #todo.priorities > 0 then
							for _, group_name in pairs(config.options.priority_groups) do
								local all_match = true
								for _, required in ipairs(group_name.members) do
									local found = false
									for _, priority in ipairs(todo.priorities) do
										if priority == required then
											found = true
											break
										end
									end
									if not found then
										all_match = false
										break
									end
								end
								if all_match then
									hl_group = group_name.hl_group or "DooingPending"
									break
								end
							end
						end
						vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, line_nr, 0, -1)
					end

					-- Apply tag highlights
					for tag in todo.text:gmatch("#(%w+)") do
						local start_idx = line:find("#" .. tag) - 1
						if start_idx then
							vim.api.nvim_buf_add_highlight(
								buf_id,
								ns_id,
								"Type",
								line_nr,
								start_idx,
								start_idx + #tag + 1
							)
						end
					end

					-- Highlight overdue status if present and todo is not done
					if not todo.done and todo.due_at and todo.due_at < os.time() then
						local overdue_str = "[OVERDUE]"
						local overdue_start = line:find(overdue_str)
						if overdue_start then
							vim.api.nvim_buf_add_highlight(
								buf_id,
								ns_id,
								"ErrorMsg",
								line_nr,
								overdue_start - 1,
								overdue_start + #overdue_str - 1
							)
						end
					end
					break
				end
			end
		elseif line:match("Search Results for:") then
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "WarningMsg", line_nr, 0, -1)
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
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_set_current_win(win_id)
		vim.ui.input({ prompt = "Search todos: " }, function(query)
			handle_search_query(query, main_win_id, render_callback)
		end)
		return
	end

	if win_id then
		win_id = nil
		buf_id = nil
	end

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
