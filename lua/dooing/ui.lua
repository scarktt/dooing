---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Explicitly declare vim as a global variable
local vim = vim

-- UI Module for Dooing Plugin
-- Handles window creation, rendering and UI interactions for todo management

---@class DoingUI
---@field toggle_todo_window function
---@field render_todos function
---@field close_window function
---@field new_todo function
---@field toggle_todo function
---@field delete_todo function
---@field delete_completed function
local M = {}

--------------------------------------------------
-- Dependencies
--------------------------------------------------
local state = require("dooing.state")

local MainWindow = require("dooing.ui.windows.main")
local HelpWindow = require("dooing.ui.windows.help")
local TagWindow = require("dooing.ui.windows.tag")
local Render = require("dooing.ui.render")
local TodoActions = require("dooing.ui.actions.todo")
local IoActions = require("dooing.ui.actions.io")
local SearchWindow = require("dooing.ui.windows.search")

--------------------------------------------------
-- Local Variables and Cache
--------------------------------------------------
---
-- Window and buffer IDs
---@type integer|nil
local win_id = nil
---@type integer|nil
local buf_id = nil

--------------------------------------------------
-- Highlights Setup
--------------------------------------------------
-- Set up highlights

local function setup_highlights()
	-- Set up base highlights
	vim.api.nvim_set_hl(0, "DooingPending", { link = "Question", default = true })
	vim.api.nvim_set_hl(0, "DooingDone", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "DooingHelpText", { link = "Directory", default = true })
end

--------------------------------------------------
-- Todo Management Functions
--------------------------------------------------

local function edit_todo()
	TodoActions.edit_todo(win_id, buf_id, M.render_todos)
end

--------------------------------------------------
-- Core Window Management
--------------------------------------------------

-- Creates and manages the help window
local function create_help_window()
	HelpWindow.create()
end

local function prompt_export()
	IoActions.prompt_export()
end

local function prompt_import(callback)
	IoActions.prompt_import(callback)
end

-- Creates and manages the tags window
local function create_tag_window()
	TagWindow.create(win_id, M.render_todos)
end

-- Search for todos
local function create_search_window()
	SearchWindow.create(win_id, M.render_todos)
end

-- Parse time estimation string (e.g., "2h", "1d", "0.5w")
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

local function add_time_estimation()
	TodoActions.add_time_estimation(win_id, state.active_filter, M.render_todos)
end

local function remove_time_estimation()
	TodoActions.remove_time_estimation(win_id, state.active_filter, M.render_todos)
end

local function add_due_date()
	TodoActions.add_due_date(win_id, state.active_filter, M.render_todos)
end

local function remove_due_date()
	TodoActions.remove_due_date(win_id, state.active_filter, M.render_todos)
end

-- Creates and configures the main todo window
local function create_window()
	setup_highlights()

	local window = MainWindow.create({
		new_todo = M.new_todo,
		toggle_todo = M.toggle_todo,
		delete_todo = M.delete_todo,
		delete_completed = M.delete_completed,
		close_window = M.close_window,
		undo_delete = function()
			if state.undo_delete() then
				M.render_todos()
				vim.notify("Todo restored", vim.log.levels.INFO)
			end
		end,
		toggle_help = create_help_window,
		toggle_tags = create_tag_window,
		clear_filter = function()
			state.set_filter(nil)
			M.render_todos()
		end,
		edit_todo = edit_todo,
		add_due_date = add_due_date,
		remove_due_date = remove_due_date,
		add_time_estimation = add_time_estimation,
		remove_time_estimation = remove_time_estimation,
		import_todos = prompt_import,
		export_todos = prompt_export,
		remove_duplicates = M.remove_duplicates,
		search_todos = create_search_window,
	})

	win_id = window.win_id
	buf_id = window.buf_id
end

-- Public Interface
--------------------------------------------------
---
-- Main function for todos rendering
function M.render_todos()
	if buf_id then
		Render.render_todos(buf_id)
	end
end

-- Toggles the main todo window visibility
function M.toggle_todo_window()
	if MainWindow.is_valid() then
		M.close_window()
	else
		create_window()
		M.render_todos()
	end
end

-- Closes all plugin windows
function M.close_window()
	HelpWindow.close()
	TagWindow.close(win_id)
	MainWindow.close()
	win_id = nil
	buf_id = nil
end

-- Creates a new todo item
function M.new_todo()
	TodoActions.new_todo(M.render_todos)
end

-- Toggles the completion status of the current todo
function M.toggle_todo()
	TodoActions.toggle_todo(win_id, buf_id, M.render_todos)
end

-- Deletes the current todo item
function M.delete_todo()
	TodoActions.delete_todo(win_id, buf_id, M.render_todos)
end

-- Deletes all completed todos
function M.delete_completed()
	TodoActions.delete_completed(M.render_todos)
end

-- Delete all duplicated todos
function M.remove_duplicates()
	TodoActions.remove_duplicates(M.render_todos)
end

return M
