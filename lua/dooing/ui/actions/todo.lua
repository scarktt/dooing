---------------------------------------------
--- Task prioritization and time sorting made by @clementpoiret
--- Due date functionality made by @derivia
---------------------------------------------

local M = {}

-- Dependencies
local config = require("dooing.config")
local state = require("dooing.state")
local calendar = require("dooing.ui.windows.calendar")

-- Helper function to parse time estimation string (e.g., "2h", "1d", "0.5w")
local function parse_time_estimation(time_str)
	local number, unit = time_str:match("^(%d+%.?%d*)([mhdw])$")

	if not (number and unit) then
		return nil,
			"Invalid format. Use number followed by m (minutes), h (hours), d (days), or w (weeks). E.g., 30m, 2h, 1d, 0.5w"
	end

	local hours = tonumber(number)
	if not hours then
		return nil, "Invalid number format"
	end

	-- Convert to hours
	if unit == "m" then
		hours = hours / 60
	elseif unit == "d" then
		hours = hours * 24
	elseif unit == "w" then
		hours = hours * 24 * 7
	end

	return hours
end

-- Create a new todo
function M.new_todo(render_callback)
	vim.ui.input({ prompt = "New to-do: " }, function(input)
		if input and input ~= "" then
			-- Check if priorities are configured
			if config.options.priorities and #config.options.priorities > 0 then
				local priorities = config.options.priorities
				local priority_options = {}
				local selected_priorities = {}

				for i, priority in ipairs(priorities) do
					priority_options[i] = string.format("[ ] %s", priority.name)
				end

				-- Create a buffer for priority selection
				local select_buf = vim.api.nvim_create_buf(false, true)
				local ui = vim.api.nvim_list_uis()[1]
				local width = 40
				local height = #priority_options + 2
				local row = math.floor((ui.height - height) / 2)
				local col = math.floor((ui.width - width) / 2)

				local select_win = vim.api.nvim_open_win(select_buf, true, {
					relative = "editor",
					width = width,
					height = height,
					row = row,
					col = col,
					style = "minimal",
					border = "rounded",
					title = " Select Priorities ",
					title_pos = "center",
					footer = string.format(" %s: toggle | <Enter>: confirm ", config.options.keymaps.toggle_priority),
					footer_pos = "center",
				})

				-- Set buffer content
				vim.api.nvim_buf_set_lines(select_buf, 0, -1, false, priority_options)
				vim.api.nvim_buf_set_option(select_buf, "modifiable", false)

				-- Add keymaps for selection
				vim.keymap.set("n", config.options.keymaps.toggle_priority, function()
					local cursor = vim.api.nvim_win_get_cursor(select_win)
					local line_num = cursor[1]
					local current_line = vim.api.nvim_buf_get_lines(select_buf, line_num - 1, line_num, false)[1]

					vim.api.nvim_buf_set_option(select_buf, "modifiable", true)
					if current_line:match("^%[%s%]") then
						-- Select item
						local new_line = current_line:gsub("^%[%s%]", "[x]")
						selected_priorities[line_num] = true
						vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
					else
						-- Deselect item
						local new_line = current_line:gsub("^%[x%]", "[ ]")
						selected_priorities[line_num] = nil
						vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
					end
					vim.api.nvim_buf_set_option(select_buf, "modifiable", false)
				end, { buffer = select_buf, nowait = true })

				-- Add keymap for confirmation
				vim.keymap.set("n", "<CR>", function()
					local selected_priority_names = {}
					for idx, _ in pairs(selected_priorities) do
						local priority = config.options.priorities[idx]
						if priority then
							table.insert(selected_priority_names, priority.name)
						end
					end

					-- Close selection window
					vim.api.nvim_win_close(select_win, true)

					-- Add todo with priority names (or nil if none selected)
					local priorities_to_add = #selected_priority_names > 0 and selected_priority_names or nil
					state.add_todo(input, priorities_to_add)

					if render_callback then
						render_callback()
					end
				end, { buffer = select_buf, nowait = true })
			else
				-- If prioritization is disabled, just add the todo without priority
				state.add_todo(input)
				if render_callback then
					render_callback()
				end
			end
		end
	end)
end

-- Edit an existing todo
function M.edit_todo(win_id, buf_id, render_callback)
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]

	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon

	if line_content:match("^%s+[" .. done_icon .. pending_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						todo_index = i
						break
					end
				end
			end
		end

		vim.ui.input({
			prompt = "Edit to-do: ",
			default = state.todos[todo_index].text,
		}, function(input)
			if input and input ~= "" then
				state.todos[todo_index].text = input
				state.save_todos()
				if render_callback then
					render_callback()
				end
			end
		end)
	end
end

-- Toggle todo completion status
function M.toggle_todo(win_id, buf_id, render_callback)
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon

	if line_content:match("^%s+[" .. done_icon .. pending_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then -- -2 for filter header
						state.toggle_todo(i)
						break
					end
				end
			end
		else
			state.toggle_todo(todo_index)
		end
		if render_callback then
			render_callback()
		end
	end
end

-- Delete a todo
function M.delete_todo(win_id, buf_id, render_callback)
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon

	if line_content:match("^%s+[" .. done_icon .. pending_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						todo_index = i
						break
					end
				end
			end
		end
		state.delete_todo_with_confirmation(todo_index, win_id, calendar, render_callback)
	end
end

-- Delete all completed todos
function M.delete_completed(render_callback)
	state.delete_completed()
	if render_callback then
		render_callback()
	end
end

-- Remove duplicate todos
function M.remove_duplicates(render_callback)
	local dups = state.remove_duplicates()
	vim.notify("Removed " .. dups .. " duplicates.", vim.log.levels.INFO)
	if render_callback then
		render_callback()
	end
end

-- Add time estimation to a todo
function M.add_time_estimation(win_id, active_filter, render_callback)
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = current_line - (active_filter and 3 or 1)

	vim.ui.input({
		prompt = "Estimated completion time (e.g., 15m, 2h, 1d, 0.5w): ",
		default = "",
	}, function(input)
		if input and input ~= "" then
			local hours, err = parse_time_estimation(input)
			if hours then
				state.add_time_estimation(todo_index, hours)
				vim.notify("Time estimation added successfully", vim.log.levels.INFO)
				if render_callback then
					render_callback()
				end
			else
				vim.notify("Error adding time estimation: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			end
		end
	end)
end

-- Remove time estimation from a todo
function M.remove_time_estimation(win_id, active_filter, render_callback)
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = current_line - (active_filter and 3 or 1)

	if state.remove_time_estimation(todo_index) then
		vim.notify("Time estimation removed successfully", vim.log.levels.INFO)
		if render_callback then
			render_callback()
		end
	else
		vim.notify("Error removing time estimation", vim.log.levels.ERROR)
	end
end

-- Add due date to a todo
function M.add_due_date(win_id, active_filter, render_callback)
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = current_line - (active_filter and 3 or 1)

	calendar.create(function(date_str)
		if date_str and date_str ~= "" then
			local success, err = state.add_due_date(todo_index, date_str)

			if success then
				vim.notify("Due date added successfully", vim.log.levels.INFO)
				if render_callback then
					render_callback()
				end
			else
				vim.notify("Error adding due date: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			end
		end
	end, { language = "en" })
end

-- Remove due date from a todo
function M.remove_due_date(win_id, active_filter, render_callback)
	local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = current_line - (active_filter and 3 or 1)

	if state.remove_due_date(todo_index) then
		vim.notify("Due date removed successfully", vim.log.levels.INFO)
		if render_callback then
			render_callback()
		end
	else
		vim.notify("Error removing due date", vim.log.levels.ERROR)
	end
end

return M
