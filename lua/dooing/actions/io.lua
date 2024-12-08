---------------------------------------------
--- Incredible feature developed by @derivia
---------------------------------------------

local M = {}

-- Dependencies
local state = require("dooing.state")

--- Validates if a file path is acceptable for IO operations
---@param file_path string The path to validate
---@return boolean is_valid
---@return string? error_message
local function validate_file_path(file_path)
	if not file_path or file_path == "" then
		return false, "No file path provided"
	end

	-- Expand the path to handle ~ and environment variables
	file_path = vim.fn.expand(file_path)

	-- Check if path contains invalid characters
	if file_path:match("[<>:|]") then
		return false, "File path contains invalid characters"
	end

	return true, nil
end

--- Ensures the directory exists for a given file path
---@param file_path string The full file path
---@return boolean success
---@return string? error_message
local function ensure_directory_exists(file_path)
	local directory = vim.fn.fnamemodify(file_path, ":h")

	if vim.fn.isdirectory(directory) == 0 then
		local success = vim.fn.mkdir(directory, "p")
		if success == 0 then
			return false, "Failed to create directory: " .. directory
		end
	end

	return true, nil
end

--- Exports todos to a JSON file
---@param file_path string The path where to export the todos
---@return boolean success
---@return string message Success or error message
function M.export_todos(file_path)
	-- Validate file path
	local is_valid, error_msg = validate_file_path(file_path)
	if not is_valid then
		return false, error_msg
	end

	-- Ensure directory exists
	local dir_ok, dir_error = ensure_directory_exists(file_path)
	if not dir_ok then
		return false, dir_error
	end

	-- Try to create or open the file
	local file = io.open(file_path, "w")
	if not file then
		return false, "Could not open file for writing: " .. file_path
	end

	-- Prepare todos for export
	local export_data = {
		version = "1.0",
		timestamp = os.time(),
		todos = state.todos,
	}

	-- Convert to JSON and write
	local success, json_content = pcall(vim.fn.json_encode, export_data)
	if not success then
		file:close()
		return false, "Failed to encode todos to JSON"
	end

	-- Write to file
	local write_success, write_error = pcall(function()
		file:write(json_content)
		file:close()
	end)

	if not write_success then
		return false, "Failed to write to file: " .. (write_error or "unknown error")
	end

	return true, string.format("Exported %d todos to %s", #state.todos, file_path)
end

--- Imports todos from a JSON file
---@param file_path string The path from where to import the todos
---@return boolean success
---@return string message Success or error message
function M.import_todos(file_path)
	-- Validate file path
	local is_valid, error_msg = validate_file_path(file_path)
	if not is_valid then
		return false, error_msg
	end

	-- Check if file exists
	if vim.fn.filereadable(file_path) == 0 then
		return false, "File does not exist: " .. file_path
	end

	-- Try to open and read the file
	local file = io.open(file_path, "r")
	if not file then
		return false, "Could not open file: " .. file_path
	end

	local content = file:read("*all")
	file:close()

	if not content or content == "" then
		return false, "File is empty"
	end

	-- Try to parse JSON
	local success, imported_data = pcall(vim.fn.json_decode, content)
	if not success then
		return false, "Invalid JSON format in file"
	end

	-- Validate imported data structure
	if type(imported_data) ~= "table" then
		return false, "Invalid data format: expected table"
	end

	local todos_to_import = imported_data.todos or imported_data
	if type(todos_to_import) ~= "table" then
		return false, "Invalid todos format: expected array"
	end

	-- Validate each todo item
	local valid_todos = {}
	local invalid_count = 0

	for _, todo in ipairs(todos_to_import) do
		if type(todo) == "table" and type(todo.text) == "string" and todo.text ~= "" then
			-- Ensure required fields exist with correct types
			todo.done = type(todo.done) == "boolean" and todo.done or false
			todo.created_at = tonumber(todo.created_at) or os.time()

			-- Optional fields validation
			if todo.priorities and type(todo.priorities) ~= "table" then
				todo.priorities = nil
			end
			if todo.due_at and type(todo.due_at) ~= "number" then
				todo.due_at = nil
			end
			if todo.estimated_hours and type(todo.estimated_hours) ~= "number" then
				todo.estimated_hours = nil
			end

			table.insert(valid_todos, todo)
		else
			invalid_count = invalid_count + 1
		end
	end

	-- Merge valid todos with existing ones
	for _, todo in ipairs(valid_todos) do
		table.insert(state.todos, todo)
	end

	-- Sort and save the updated todos
	state.sort_todos()
	state.save_todos()

	local message = string.format("Imported %d todos", #valid_todos)
	if invalid_count > 0 then
		message = message .. string.format(" (skipped %d invalid entries)", invalid_count)
	end

	return true, message
end

return M
