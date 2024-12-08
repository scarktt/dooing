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
function M.parse_time_estimation(time_str)
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

-- Core todo actions
function M.create_todo(text, priorities, callback)
	state.add_todo(text, priorities)
	if callback then
		callback()
	end
end

function M.edit_todo(index, new_text, callback)
	if state.todos[index] then
		state.todos[index].text = new_text
		state.save_todos()
		if callback then
			callback()
		end
	end
end

function M.toggle_todo(index, callback)
	state.toggle_todo(index)
	if callback then
		callback()
	end
end

function M.delete_todo(index, win_id, callback)
	state.delete_todo_with_confirmation(index, win_id, calendar, callback)
end

function M.delete_completed(callback)
	state.delete_completed()
	if callback then
		callback()
	end
end

function M.remove_duplicates(callback)
	local dups = state.remove_duplicates()
	vim.notify("Removed " .. dups .. " duplicates.", vim.log.levels.INFO)
	if callback then
		callback()
	end
end

-- Time estimation actions
function M.add_time_estimation(index, time_str, callback)
	local hours, err = M.parse_time_estimation(time_str)
	if hours then
		local success = state.add_time_estimation(index, hours)
		if success then
			vim.notify("Time estimation added successfully", vim.log.levels.INFO)
			if callback then
				callback()
			end
			return true
		end
	end
	vim.notify("Error adding time estimation: " .. (err or "Unknown error"), vim.log.levels.ERROR)
	return false
end

function M.remove_time_estimation(index, callback)
	if state.remove_time_estimation(index) then
		vim.notify("Time estimation removed successfully", vim.log.levels.INFO)
		if callback then
			callback()
		end
		return true
	end
	vim.notify("Error removing time estimation", vim.log.levels.ERROR)
	return false
end

-- Due date actions
function M.add_due_date(index, date_str, callback)
	local success, err = state.add_due_date(index, date_str)
	if success then
		vim.notify("Due date added successfully", vim.log.levels.INFO)
		if callback then
			callback()
		end
		return true
	end
	vim.notify("Error adding due date: " .. (err or "Unknown error"), vim.log.levels.ERROR)
	return false
end

function M.remove_due_date(index, callback)
	if state.remove_due_date(index) then
		vim.notify("Due date removed successfully", vim.log.levels.INFO)
		if callback then
			callback()
		end
		return true
	end
	vim.notify("Error removing due date", vim.log.levels.ERROR)
	return false
end

return M
