local M = {}

-- Dependencies
local config = require("dooing.config")
local state = require("dooing.state")
local calendar = require("dooing.ui.windows.calendar")

-- Window and buffer IDs for each column
local windows = {
	todo = { win_id = nil, buf_id = nil },
	doing = { win_id = nil, buf_id = nil },
	done = { win_id = nil, buf_id = nil },
}

-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing_kanban")

-- Function to close all kanban windows
local function close_all_windows()
	for _, win in pairs(windows) do
		if win.win_id and vim.api.nvim_win_is_valid(win.win_id) then
			vim.api.nvim_win_close(win.win_id, true)
		end
		win.win_id = nil
		win.buf_id = nil
	end
end

-- Function to find todo line number in buffer
local function find_todo_line(buf_id, todo_text)
	if not buf_id then
		return nil
	end
	local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
	for i, line in ipairs(lines) do
		if line == todo_text then
			return i
		end
	end
	return nil
end

-- Function to format a todo item with all its properties
local function format_todo(todo)
	local parts = {}
	local icon = todo.done and config.options.formatting.done.icon or config.options.formatting.pending.icon

	table.insert(parts, "  " .. icon)
	table.insert(parts, todo.text)

	-- Add due date if exists
	if todo.due_at then
		local date = os.date("*t", todo.due_at)
		local month = calendar.MONTH_NAMES[config.options.calendar.language or "en"][date.month]
		local formatted_date = string.format("%s %d, %d", month, date.day, date.year)

		if config.options.calendar.icon and config.options.calendar.icon ~= "" then
			table.insert(parts, "[" .. config.options.calendar.icon .. " " .. formatted_date .. "]")
		else
			table.insert(parts, "[" .. formatted_date .. "]")
		end

		if not todo.done and todo.due_at < os.time() then
			table.insert(parts, "[OVERDUE]")
		end
	end

	-- Add estimated time if exists
	if todo.estimated_hours then
		local time_str
		if todo.estimated_hours >= 168 then -- more than a week
			local weeks = todo.estimated_hours / 168
			time_str = string.format("[≈ %gw]", weeks)
		elseif todo.estimated_hours >= 24 then -- more than a day
			local days = todo.estimated_hours / 24
			time_str = string.format("[≈ %gd]", days)
		elseif todo.estimated_hours >= 1 then -- more than an hour
			time_str = string.format("[≈ %gh]", todo.estimated_hours)
		else -- less than an hour
			time_str = string.format("[≈ %gm]", todo.estimated_hours * 60)
		end
		table.insert(parts, time_str)
	end

	return table.concat(parts, " ")
end

-- Function to get priority highlight for a todo
local function get_todo_highlight(todo)
	if todo.done then
		return "DooingDone"
	end

	if not config.options.priorities or #config.options.priorities == 0 then
		return "DooingPending"
	end

	if todo.priorities and #todo.priorities > 0 and config.options.priority_groups then
		for _, group_data in pairs(config.options.priority_groups) do
			local all_members_match = true
			for _, member in ipairs(group_data.members) do
				local found = false
				for _, priority in ipairs(todo.priorities) do
					if priority == member then
						found = true
						break
					end
				end
				if not found then
					all_members_match = false
					break
				end
			end

			if all_members_match then
				return group_data.hl_group or "DooingPending"
			end
		end
	end

	return "DooingPending"
end

-- Function to render a single column
local function render_column(buf_id, todos)
	if not buf_id then
		return
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

	local lines = {}
	local highlights = {}

	for _, todo in ipairs(todos) do
		local formatted_todo = format_todo(todo)
		table.insert(lines, formatted_todo)
		table.insert(highlights, {
			line = #lines - 1,
			hl_group = get_todo_highlight(todo),
		})
	end

	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl.hl_group, hl.line, 0, -1)

		-- Highlight tags
		local line = lines[hl.line + 1]
		for tag in line:gmatch("#(%w+)") do
			local start_idx = line:find("#" .. tag) - 1
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Type", hl.line, start_idx, start_idx + #tag + 1)
		end

		-- Highlight due date
		local due_date_start = line:find("%[[@]")
		local overdue_start = line:find("%[OVERDUE%]")
		if due_date_start then
			vim.api.nvim_buf_add_highlight(
				buf_id,
				ns_id,
				"Comment",
				hl.line,
				due_date_start - 1,
				overdue_start and overdue_start - 1 or -1
			)
		end
		if overdue_start then
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "ErrorMsg", hl.line, overdue_start - 1, -1)
		end
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

-- Function to render all columns
local function render_board()
	-- Organize todos
	local columns = {
		todo = {},
		doing = {},
		done = {},
	}

	for _, todo in ipairs(state.todos) do
		if todo.done then
			table.insert(columns.done, todo)
		elseif todo.text:match("#doing") then
			table.insert(columns.doing, todo)
		else
			table.insert(columns.todo, todo)
		end
	end

	-- Render each column
	render_column(windows.todo.buf_id, columns.todo)
	render_column(windows.doing.buf_id, columns.doing)
	render_column(windows.done.buf_id, columns.done)
end

-- Function to get current todo under cursor
local function get_current_todo()
	local current_win = vim.api.nvim_get_current_win()
	local current_buf = vim.api.nvim_win_get_buf(current_win)
	local cursor = vim.api.nvim_win_get_cursor(current_win)
	local line = cursor[1]

	local line_text = vim.api.nvim_buf_get_lines(current_buf, line - 1, line, false)[1]

	-- Find which column we're in
	local column
	for name, win in pairs(windows) do
		if win.win_id == current_win then
			column = name
			break
		end
	end

	-- Find todo index
	for i, todo in ipairs(state.todos) do
		if line_text:find(todo.text, 1, true) then
			return i, column, todo.text
		end
	end

	return nil
end

-- Function to move todo between columns
local function move_todo(direction)
	local todo_index, current_col, todo_text = get_current_todo()
	if not todo_index or not current_col then
		return
	end

	local todo = state.todos[todo_index]
	if not todo then
		return
	end

	local target_col
	if direction == "right" then
		if current_col == "todo" then
			todo.text = todo.text .. " #doing"
			target_col = "doing"
		elseif current_col == "doing" then
			todo.done = true
			todo.text = todo.text:gsub("#doing", "")
			target_col = "done"
		end
	elseif direction == "left" then
		if current_col == "doing" then
			todo.text = todo.text:gsub("#doing", "")
			target_col = "todo"
		elseif current_col == "done" then
			todo.done = false
			if not todo.text:match("#doing") then
				todo.text = todo.text .. " #doing"
			end
			target_col = "doing"
		end
	end

	if target_col then
		state.save_todos()
		render_board()

		-- Focus the target window and move cursor to the todo
		vim.api.nvim_set_current_win(windows[target_col].win_id)
		local new_line = find_todo_line(windows[target_col].buf_id, todo.text)
		if new_line then
			vim.api.nvim_win_set_cursor(windows[target_col].win_id, { new_line, 0 })
		end
	end
end

-- Create and configure Kanban windows
function M.create()
	if windows.todo.win_id and vim.api.nvim_win_is_valid(windows.todo.win_id) then
		close_all_windows()
		return
	end

	local ui = vim.api.nvim_list_uis()[1]
	local col_width = 40 -- Fixed column width
	local total_width = col_width * 3 + 4 -- Total width plus padding
	local height = math.floor(ui.height * 0.3) -- Reduced height
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - total_width) / 2)

	local columns = { "todo", "doing", "done" }
	for i, name in ipairs(columns) do
		local buf = vim.api.nvim_create_buf(false, true)
		windows[name].buf_id = buf

		windows[name].win_id = vim.api.nvim_open_win(buf, i == 1, {
			relative = "editor",
			row = row,
			col = col + (i - 1) * (col_width + 2),
			width = col_width,
			height = height,
			style = "minimal",
			border = "rounded",
			title = " " .. string.upper(name) .. " ",
			title_pos = "center",
		})

		-- Buffer options
		vim.api.nvim_buf_set_option(buf, "modifiable", false)
		vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

		-- Keymaps
		local keyopts = { buffer = buf, nowait = true }
		vim.keymap.set("n", "h", function()
			move_todo("left")
		end, keyopts)
		vim.keymap.set("n", "l", function()
			move_todo("right")
		end, keyopts)
		vim.keymap.set("n", "q", close_all_windows, keyopts)
		vim.keymap.set("n", "<Tab>", function()
			local current_win = vim.api.nvim_get_current_win()
			local next_col
			if current_win == windows.todo.win_id then
				next_col = "doing"
			elseif current_win == windows.doing.win_id then
				next_col = "done"
			elseif current_win == windows.done.win_id then
				next_col = "todo"
			end
			if next_col then
				vim.api.nvim_set_current_win(windows[next_col].win_id)
			end
		end, keyopts)

		vim.keymap.set("n", "<S-Tab>", function()
			local current_win = vim.api.nvim_get_current_win()
			local prev_col
			if current_win == windows.todo.win_id then
				prev_col = "done"
			elseif current_win == windows.doing.win_id then
				prev_col = "todo"
			elseif current_win == windows.done.win_id then
				prev_col = "doing"
			end
			if prev_col then
				vim.api.nvim_set_current_win(windows[prev_col].win_id)
			end
		end, keyopts)
	end

	render_board()
end

return M
