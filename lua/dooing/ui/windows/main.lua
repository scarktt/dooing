local M = {}

-- Dependencies
local config = require("dooing.config")
local state = require("dooing.state")
local actions = require("dooing.actions.todo")
local io_actions = require("dooing.actions.io")

-- Local window IDs and buffers
local win_id = nil
local buf_id = nil

-- Helper function to get current todo index considering active filter
local function get_todo_index()
	local cursor = vim.api.nvim_win_get_cursor(win_id)[1]
	local line_content = vim.api.nvim_buf_get_lines(buf_id, cursor - 1, cursor, false)[1]
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon

	-- Check if we're on a todo line
	if not line_content or not line_content:match("^%s+[" .. done_icon .. pending_icon .. "]") then
		return nil
	end

	if state.active_filter then
		local visible_index = 0
		for i, todo in ipairs(state.todos) do
			if todo.text:match("#" .. state.active_filter) then
				visible_index = visible_index + 1
				if visible_index == cursor - 2 then -- -2 for filter header
					return i
				end
			end
		end
	else
		return cursor - 1
	end

	return nil
end

-- Creates and configures the quick keys window
local function create_quick_keys_window(main_win_pos)
	if not config.options.quick_keys then
		return nil
	end

	local quick_buf = vim.api.nvim_create_buf(false, true)
	local width = config.options.window.width

	-- Define two separate line arrays for each column
	local lines_1 = {
		"",
		"  i - New todo",
		"  x - Toggle todo",
		"  d - Delete todo",
		"  u - Undo delete",
		"  H - Add due date",
		"",
	}

	local lines_2 = {
		"",
		"  T - Add time",
		"  t - Tags",
		"  / - Search",
		"  I - Import",
		"  E - Export",
		"",
	}

	-- Calculate middle point for even spacing
	local mid_point = math.floor(width / 2)
	local padding = 2

	-- Create combined lines with centered columns
	local lines = {}
	for i = 1, #lines_1 do
		local line1 = lines_1[i] .. string.rep(" ", mid_point - #lines_1[i] - padding)
		local line2 = lines_2[i] or ""
		lines[i] = line1 .. line2
	end

	vim.api.nvim_buf_set_lines(quick_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(quick_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(quick_buf, "buftype", "nofile")

	-- Position it under the main window
	local row = main_win_pos.row + main_win_pos.height + 1

	local quick_win = vim.api.nvim_open_win(quick_buf, false, {
		relative = "editor",
		row = row,
		col = main_win_pos.col,
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 45,
		footer = " Quick Keys ",
		footer_pos = "center",
	})

	-- Add highlights
	local ns = vim.api.nvim_create_namespace("dooing_quick_keys")

	-- Highlight quick keys elements
	for i = 1, #lines do
		-- Left column
		if i > 1 and i < #lines then
			vim.api.nvim_buf_add_highlight(quick_buf, ns, "DooingQuickKey", i - 1, 2, 3)
			vim.api.nvim_buf_add_highlight(quick_buf, ns, "DooingQuickDesc", i - 1, 5, mid_point - padding)

			-- Right column
			local right_key_start = mid_point
			vim.api.nvim_buf_add_highlight(
				quick_buf,
				ns,
				"DooingQuickKey",
				i - 1,
				right_key_start + 2,
				right_key_start + 3
			)
			vim.api.nvim_buf_add_highlight(quick_buf, ns, "DooingQuickDesc", i - 1, right_key_start + 5, -1)
		end
	end

	return quick_win
end

-- Setup window keymaps
local function setup_window_keymaps(buf_id, callbacks)
	local keyopts = { buffer = buf_id, nowait = true }

	-- Map each configured keymap to its callback
	for action, key in pairs(config.options.keymaps) do
		if callbacks[action] then
			vim.keymap.set("n", key, callbacks[action], keyopts)
		end
	end
end

-- Create and configure main window
function M.create(callbacks)
	-- Configure window dimensions
	local ui = vim.api.nvim_list_uis()[1]
	local width = config.options.window.width
	local height = config.options.window.height
	local col = math.floor((ui.width - width) / 2)
	local row = math.floor((ui.height - height) / 2)

	-- Create buffer
	buf_id = vim.api.nvim_create_buf(false, true)

	-- Create window
	win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " to-dos ",
		title_pos = "center",
		footer = " [?] for help ",
		footer_pos = "center",
	})

	-- Create quick keys window
	local quick_win = create_quick_keys_window({
		row = row,
		col = col,
		width = width,
		height = height,
	})

	-- Close quick keys window when main window is closed
	if quick_win then
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win_id),
			callback = function()
				if vim.api.nvim_win_is_valid(quick_win) then
					vim.api.nvim_win_close(quick_win, true)
				end
			end,
		})
	end

	-- Set window options
	vim.api.nvim_win_set_option(win_id, "wrap", true)
	vim.api.nvim_win_set_option(win_id, "linebreak", true)
	vim.api.nvim_win_set_option(win_id, "breakindent", true)
	vim.api.nvim_win_set_option(win_id, "breakindentopt", "shift:2")
	vim.api.nvim_win_set_option(win_id, "showbreak", " ")

	-- Enhanced callbacks with action integration
	local enhanced_callbacks = {
		new_todo = function()
			vim.ui.input({ prompt = "New to-do: " }, function(input)
				if input and input ~= "" then
					actions.create_todo(input, nil, callbacks.render_todos)
				end
			end)
		end,
		toggle_todo = function()
			local index = get_todo_index()
			if index then
				actions.toggle_todo(index, callbacks.render_todos)
			end
		end,
		delete_todo = function()
			local index = get_todo_index()
			if index then
				actions.delete_todo(index, win_id, callbacks.render_todos)
			end
		end,
		delete_completed = function()
			actions.delete_completed(callbacks.render_todos)
		end,
		add_time_estimation = function()
			local index = get_todo_index()
			if index then
				vim.ui.input({
					prompt = "Estimated completion time (e.g., 15m, 2h, 1d, 0.5w): ",
				}, function(input)
					if input and input ~= "" then
						actions.add_time_estimation(index, input, callbacks.render_todos)
					end
				end)
			end
		end,

		remove_time_estimation = function()
			local index = get_todo_index()
			if index then
				actions.remove_time_estimation(index, callbacks.render_todos)
			end
		end,
		add_due_date = function()
			local index = get_todo_index()
			if index then
				callbacks.add_due_date(index, callbacks.render_todos)
			else
				vim.notify("Please select a valid todo item", vim.log.levels.WARN)
			end
		end,
		import_todos = function()
			vim.ui.input({
				prompt = "Import todos from file: ",
				completion = "file",
				default = vim.fn.expand("~/todos.json"),
			}, function(file_path)
				if file_path and file_path ~= "" then
					local success, message = io_actions.import_todos(file_path)
					vim.notify(message, success and vim.log.levels.INFO or vim.log.levels.ERROR)
					if success and callbacks.render_todos then
						callbacks.render_todos()
					end
				end
			end)
		end,
		export_todos = function()
			vim.ui.input({
				prompt = "Export todos to file: ",
				completion = "file",
				default = vim.fn.expand("~/todos.json"),
			}, function(file_path)
				if file_path and file_path ~= "" then
					local success, message = io_actions.export_todos(file_path)
					vim.notify(message, success and vim.log.levels.INFO or vim.log.levels.ERROR)
				end
			end)
		end,
		remove_duplicates = function()
			actions.remove_duplicates(callbacks.render_todos)
		end,
	}

	-- Merge provided callbacks with enhanced ones
	for k, v in pairs(callbacks) do
		if not enhanced_callbacks[k] then
			enhanced_callbacks[k] = v
		end
	end

	-- Setup keymaps
	setup_window_keymaps(buf_id, enhanced_callbacks)

	return {
		win_id = win_id,
		buf_id = buf_id,
	}
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
