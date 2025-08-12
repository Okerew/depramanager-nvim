local M = {}
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local uv = vim.loop

-- Define highlight groups
local function setup_highlights()
	vim.api.nvim_set_hl(0, "OutdatedVersion", { fg = "#f38ba8", bg = "#45475a", bold = true }) -- Red background for outdated
	vim.api.nvim_set_hl(0, "OutdatedVersionText", { fg = "#6c7086", italic = true }) -- Shadowy current version
	vim.api.nvim_set_hl(0, "AvailableVersion", { fg = "#a6e3a1", italic = true }) -- Green for available version in virtual text
end

-- Global store for outdated packages
local outdated_packages = {}

-- Helper to add virtual text showing available versions
local function add_virtual_text(bufnr, line_num, current_version, available_version, package_name)
	local ns_id = vim.api.nvim_create_namespace("outdated_versions")
	local virt_text = string.format("  → %s available", available_version)

	vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num, 0, {
		virt_text = { { virt_text, "AvailableVersion" } },
		virt_text_pos = "eol",
	})
end

-- Helper to highlight outdated version in buffer
local function highlight_version_in_buffer(bufnr, line_num, line_content, package_name, current_version)
	local ns_id = vim.api.nvim_create_namespace("outdated_versions")

	-- Find the version in the line and highlight it
	local version_start, version_end = line_content:find(vim.pesc(current_version))
	if version_start then
		vim.api.nvim_buf_add_highlight(bufnr, ns_id, "OutdatedVersion", line_num, version_start - 1, version_end)
	end
end

-- Clear all highlighting and virtual text
local function clear_highlights(bufnr)
	local ns_id = vim.api.nvim_create_namespace("outdated_versions")
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

-- Cache for buffer mappings to avoid repeated lookups
local buffer_cache = {}
local file_patterns = {
	python = { "requirements%.txt$" },
	go = { "go%.mod$" },
	npm = { "package%.json$" },
}

-- Rebuild buffer cache when needed
local function rebuild_buffer_cache()
	buffer_cache = { python = {}, go = {}, npm = {} }

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local buf_name = vim.api.nvim_buf_get_name(bufnr)
			if buf_name and buf_name ~= "" then
				-- Check each file type pattern
				for lang, patterns in pairs(file_patterns) do
					for _, pattern in ipairs(patterns) do
						if buf_name:match(pattern) then
							table.insert(buffer_cache[lang], {
								bufnr = bufnr,
								name = buf_name,
								filename = buf_name:match("([^/]+)$") or "",
							})
							break
						end
					end
				end
			end
		end
	end
end

-- Cache file existence checks
local file_exists_cache = {}
local function file_exists_cached(filepath)
	if file_exists_cache[filepath] == nil then
		file_exists_cache[filepath] = vim.fn.filereadable(filepath) == 1
	end
	return file_exists_cache[filepath]
end

-- Clear caches when files change
local function clear_caches()
	buffer_cache = {}
	file_exists_cache = {}
end

-- Python file highlighting
local function highlight_python_files()
	if not buffer_cache.python then
		rebuild_buffer_cache()
	end

	for _, buf_info in ipairs(buffer_cache.python) do
		local bufnr, filename = buf_info.bufnr, buf_info.filename

		if filename == "requirements.txt" then
			local filepath = vim.fn.getcwd() .. "/" .. filename
			if not file_exists_cached(filepath) then
				goto continue
			end

			clear_highlights(bufnr)
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

			-- Pre-compile common patterns
			local package_pattern = "^([%w%-_%.]+)[=<>~!]+([%d%.%w%-%.]+)"

			for line_num, line_content in ipairs(lines) do
				if line_content ~= "" and not line_content:match("^%s*#") then -- Skip empty lines and comments
					local package, version = line_content:match(package_pattern)
					if package and version and outdated_packages.python and outdated_packages.python[package] then
						line_num = line_num - 1 -- Convert to 0-indexed
						highlight_version_in_buffer(bufnr, line_num, line_content, package, version)
						add_virtual_text(bufnr, line_num, version, outdated_packages.python[package], package)
					end
				end
			end
		end
		::continue::
	end
end

-- Go file highlighting
local function highlight_go_mod()
	if not buffer_cache.go then
		rebuild_buffer_cache()
	end

	for _, buf_info in ipairs(buffer_cache.go) do
		local bufnr = buf_info.bufnr
		local filepath = vim.fn.getcwd() .. "/go.mod"
		if not file_exists_cached(filepath) then
			goto continue
		end

		clear_highlights(bufnr)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		-- Pre-compile pattern
		local module_pattern = "^%s*([%w%.%-_/]+)%s+v([%d%.%w%-%.]+)"

		for line_num, line_content in ipairs(lines) do
			if line_content ~= "" and not line_content:match("^%s*//") then -- Skip empty lines and comments
				local module, version = line_content:match(module_pattern)
				if module and version and outdated_packages.go and outdated_packages.go[module] then
					line_num = line_num - 1 -- Convert to 0-indexed
					local full_version = "v" .. version
					highlight_version_in_buffer(bufnr, line_num, line_content, module, full_version)
					add_virtual_text(bufnr, line_num, full_version, outdated_packages.go[module], module)
				end
			end
		end
		::continue::
	end
end

-- Npm file highlighting
local function highlight_package_json()
	if not buffer_cache.npm then
		rebuild_buffer_cache()
	end

	for _, buf_info in ipairs(buffer_cache.npm) do
		local bufnr = buf_info.bufnr
		local filepath = vim.fn.getcwd() .. "/package.json"
		if not file_exists_cached(filepath) then
			goto continue
		end

		clear_highlights(bufnr)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		-- Pre-compile pattern and track if we're in dependencies section
		local package_pattern = '"([%w%-@/]+)"%s*:%s*"[%^~]?([%d%.%w%-]+)"'
		local in_deps_section = false

		for line_num, line_content in ipairs(lines) do
			-- Optimize by only checking lines in dependency sections
			if line_content:match('"dependencies"') or line_content:match('"devDependencies"') then
				in_deps_section = true
				goto continue_line
			elseif line_content:match("^%s*}") then
				in_deps_section = false
				goto continue_line
			end

			if in_deps_section and line_content ~= "" then
				local package, version = line_content:match(package_pattern)
				if package and version and outdated_packages.npm and outdated_packages.npm[package] then
					line_num = line_num - 1 -- Convert to 0-indexed
					highlight_version_in_buffer(bufnr, line_num, line_content, package, version)
					add_virtual_text(bufnr, line_num, version, outdated_packages.npm[package], package)
				end
			end
			::continue_line::
		end
		::continue::
	end
end

-- Helper to create Telescope pickers
local function create_picker(title, results)
	pickers
		.new({}, {
			prompt_title = title,
			finder = finders.new_table({ results = results }),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				map("i", "<CR>", function()
					local selection = action_state.get_selected_entry()
					if not selection then
						vim.notify("No selection made", vim.log.levels.WARN)
						return
					end
					actions.close(prompt_bufnr)
					vim.notify("Selected: " .. selection[1])
				end)
				return true
			end,
		})
		:find()
end

-- Helper to get outdated packages data
local function get_python_outdated()
	local function find_venv()
		local paths = { ".venv", "venv", "env" }
		for _, dir in ipairs(paths) do
			local full = vim.fn.getcwd() .. "/" .. dir
			local python = full .. "/bin/python"
			if uv.fs_stat(python) then
				return python
			end
		end
		return nil
	end

	local python = find_venv()
	if not python then
		local system_python = vim.fn.exepath("python3") or vim.fn.exepath("python")
		if not system_python then
			return nil, "No Python executable found"
		end
		python = system_python
	end

	local cmd = python .. " -m pip list --outdated --format=columns"
	local results = vim.fn.systemlist(cmd)

	if vim.v.shell_error ~= 0 then
		return nil, "pip list --outdated failed: " .. (results[1] or "unknown error")
	end

	if #results <= 2 then
		return {}, nil
	end

	local packages = {}
	local display_results = {}

	-- Skip header lines (usually first 2 lines)
	for i = 3, #results do
		local line = results[i]
		if line and line:match("%S") then
			local package, current, available = line:match("^(%S+)%s+(%S+)%s+(%S+)")
			if package and current and available then
				packages[package] = available
				table.insert(display_results, string.format("%s: %s → %s", package, current, available))
			end
		end
	end

	return packages, nil, display_results
end

local function get_go_outdated()
	local results = vim.fn.systemlist("go list -m -u all")
	if vim.v.shell_error ~= 0 or #results == 0 then
		return nil, "Go command failed or no modules found"
	end

	local packages = {}
	local display_results = {}

	for _, line in ipairs(results) do
		if line:find("=>") then
			local module, versions = line:match("^(.-)%s+(.+)")
			if module and versions then
				local current, available = versions:match("^(.-)%s*=>%s*(.+)")
				if current and available then
					available = available:match("^(%S+)")
					packages[module] = available
					table.insert(display_results, string.format("%s: %s → %s", module, current, available))
				end
			end
		end
	end

	return packages, nil, display_results
end

local function get_npm_outdated()
	local cwd = vim.fn.getcwd()
	if not vim.fn.filereadable(cwd .. "/package.json") then
		return nil, "No package.json found in project"
	end

	if not vim.fn.isdirectory(cwd .. "/node_modules") then
		return nil, "No node_modules/ found — run `npm install` first"
	end

	local cmd = "npm outdated --depth=0 --color=false"
	local results = vim.fn.systemlist(cmd)

	if #results == 0 then
		if vim.v.shell_error ~= 0 then
			return nil, "npm outdated failed (exit code: " .. vim.v.shell_error .. ")"
		else
			return {}, nil
		end
	end

	local packages = {}
	local display_results = {}

	-- Remove header line if present
	local start_idx = 1
	if results[1] and results[1]:match("^Package") then
		start_idx = 2
	end

	for i = start_idx, #results do
		local line = results[i]
		if line and line ~= "" then
			local parts = {}
			for part in line:gmatch("%S+") do
				table.insert(parts, part)
			end

			if #parts >= 4 then
				local package = parts[1]
				local current = parts[2]
				local wanted = parts[3]
				local latest = parts[4]

				local available = wanted ~= latest and wanted or latest
				packages[package] = available
				table.insert(display_results, string.format("%s: %s → %s", package, current, available))
			end
		end
	end

	return packages, nil, display_results
end

-- === VULNERABILITY SCANNING FUNCTIONS ===

local function get_python_vulnerabilities()
	-- Check if safety is available
	local safety_path = vim.fn.exepath("safety")
	if not safety_path or safety_path == "" or not uv.fs_stat(safety_path) then
		return nil, "Safety tool not found. Install it with: pip install safety"
	end

	-- Run the actual safety check
	local cmd = safety_path .. " check --json"
	local results = vim.fn.systemlist(cmd)

	if vim.v.shell_error ~= 0 then
		return nil, "Safety scan failed: " .. (results[1] or "unknown error")
	end

	local json_str = table.concat(results, "\n")
	if json_str == "" or json_str == "[]" then
		return {}, nil, {}
	end

	-- Very simple parser for vulnerabilities
	local packages = {}
	local display_results = {}

	for package_name, vuln_id, advisory in
		json_str:gmatch('"package_name":%s*"([^"]+)".-"vulnerability_id":%s*"([^"]+)".-"advisory":%s*"([^"]+)"')
	do
		if not packages[package_name] then
			packages[package_name] = { severity = "medium", count = 0, vulns = {} }
		end
		packages[package_name].count = packages[package_name].count + 1
		table.insert(packages[package_name].vulns, { id = vuln_id, advisory = advisory })

		table.insert(
			display_results,
			string.format(
				"[%s] %s: %s - %s...",
				packages[package_name].severity:upper(),
				package_name,
				vuln_id,
				advisory:sub(1, 80)
			)
		)
	end

	return packages, nil, display_results
end

local function get_go_vulnerabilities()
	-- Check if govulncheck is available
	local govuln_check = vim.fn.exepath("govulncheck")
	if not govuln_check then
		return nil, "govulncheck not found. Install with: go install golang.org/x/vuln/cmd/govulncheck@latest"
	end

	local cmd = "govulncheck -json ./..."
	local results = vim.fn.systemlist(cmd)

	if vim.v.shell_error ~= 0 then
		return nil, "govulncheck scan failed: " .. (results[1] or "unknown error")
	end

	local packages = {}
	local display_results = {}

	-- Parse govulncheck JSON output
	for _, line in ipairs(results) do
		if line:match('"finding"') then
			-- Extract vulnerability info from JSON line
			local module = line:match('"module":%s*"([^"]+)"')
			local vuln_id = line:match('"OSV":%s*"([^"]+)"')
			local summary = line:match('"summary":%s*"([^"]+)"')

			if module and vuln_id then
				if not packages[module] then
					packages[module] = { severity = "medium", count = 0, vulns = {} }
				end
				packages[module].count = packages[module].count + 1
				table.insert(packages[module].vulns, { id = vuln_id, summary = summary or "No summary available" })

				table.insert(
					display_results,
					string.format(
						"[%s] %s: %s - %s",
						packages[module].severity:upper(),
						module,
						vuln_id,
						(summary or "No summary"):sub(1, 80) .. "..."
					)
				)
			end
		end
	end

	return packages, nil, display_results
end

local function get_npm_vulnerabilities()
	local cwd = vim.fn.getcwd()
	if not vim.fn.filereadable(cwd .. "/package.json") then
		return nil, "No package.json found in project"
	end

	local cmd = "npm audit --json"
	local results = vim.fn.systemlist(cmd)

	if vim.v.shell_error ~= 0 and vim.v.shell_error ~= 1 then
		return nil, "npm audit failed (exit code: " .. vim.v.shell_error .. ")"
	end

	local json_str = table.concat(results, "\n")
	if json_str == "" then
		return {}, nil, {}
	end

	local packages = {}
	local display_results = {}

	-- Parse npm audit JSON output (simplified)
	-- Look for vulnerability patterns in the JSON
	for vuln_match in json_str:gmatch('"module_name":%s*"([^"]+)".-"severity":%s*"([^"]+)".-"title":%s*"([^"]+)"') do
		local package_name, severity, title = vuln_match:match("([^,]+),([^,]+),(.+)")
		if package_name and severity and title then
			if not packages[package_name] then
				packages[package_name] = { severity = severity, count = 0, vulns = {} }
			else
				-- Use highest severity
				local current_sev = packages[package_name].severity
				if
					(severity == "critical")
					or (severity == "high" and current_sev ~= "critical")
					or (severity == "medium" and current_sev == "low")
				then
					packages[package_name].severity = severity
				end
			end
			packages[package_name].count = packages[package_name].count + 1
			table.insert(packages[package_name].vulns, { title = title })

			table.insert(
				display_results,
				string.format("[%s] %s: %s", severity:upper(), package_name, title:sub(1, 100) .. "...")
			)
		end
	end

	return packages, nil, display_results
end

-- === TELESCOPE FUNCTIONS (show picker only) ===

function M.python_telescope()
	local packages, error_msg, display_results = get_python_outdated()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.ERROR)
		return
	end

	if #display_results == 0 then
		vim.notify("No outdated Python packages", vim.log.levels.INFO)
		return
	end

	create_picker("Outdated Python Packages", display_results)
end

function M.go_telescope()
	local packages, error_msg, display_results = get_go_outdated()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.INFO)
		return
	end

	if #display_results == 0 then
		vim.notify("No outdated Go modules", vim.log.levels.INFO)
		return
	end

	create_picker("Outdated Go Modules", display_results)
end

function M.npm_telescope()
	local packages, error_msg, display_results = get_npm_outdated()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.ERROR)
		return
	end

	if #display_results == 0 then
		vim.notify("No outdated npm packages", vim.log.levels.INFO)
		return
	end

	create_picker("Outdated npm Packages", display_results)
end

-- === VULNERABILITY TELESCOPE FUNCTIONS ===

function M.python_vulnerabilities_telescope()
	local packages, error_msg, display_results = get_python_vulnerabilities()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.ERROR)
		return
	end

	if #display_results == 0 then
		vim.notify("No Python vulnerabilities found", vim.log.levels.INFO)
		return
	end

	create_picker("Python Security Vulnerabilities", display_results)
end

function M.go_vulnerabilities_telescope()
	local packages, error_msg, display_results = get_go_vulnerabilities()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.ERROR)
		return
	end

	if #display_results == 0 then
		vim.notify("No Go vulnerabilities found", vim.log.levels.INFO)
		return
	end

	create_picker("Go Security Vulnerabilities", display_results)
end

function M.npm_vulnerabilities_telescope()
	local packages, error_msg, display_results = get_npm_vulnerabilities()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.ERROR)
		return
	end

	if #display_results == 0 then
		vim.notify("No npm vulnerabilities found", vim.log.levels.INFO)
		return
	end

	create_picker("npm Security Vulnerabilities", display_results)
end

-- === HIGHLIGHTING FUNCTIONS (highlight files only) ===

function M.python_highlight()
	setup_highlights()

	local packages, error_msg = get_python_outdated()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.ERROR)
		return
	end

	if not packages or vim.tbl_isempty(packages) then
		vim.notify("No outdated Python packages to highlight", vim.log.levels.INFO)
		return
	end

	outdated_packages.python = packages
	highlight_python_files()

	local count = vim.tbl_count(packages)
	vim.notify(string.format("Highlighted %d outdated Python packages in files", count), vim.log.levels.INFO)
end

function M.go_highlight()
	setup_highlights()

	local packages, error_msg = get_go_outdated()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.INFO)
		return
	end

	if not packages or vim.tbl_isempty(packages) then
		vim.notify("No outdated Go modules to highlight", vim.log.levels.INFO)
		return
	end

	outdated_packages.go = packages
	highlight_go_mod()

	local count = vim.tbl_count(packages)
	vim.notify(string.format("Highlighted %d outdated Go modules in files", count), vim.log.levels.INFO)
end

function M.npm_highlight()
	setup_highlights()

	local packages, error_msg = get_npm_outdated()

	if error_msg then
		vim.notify(error_msg, vim.log.levels.ERROR)
		return
	end

	if not packages or vim.tbl_isempty(packages) then
		vim.notify("No outdated npm packages to highlight", vim.log.levels.INFO)
		return
	end

	outdated_packages.npm = packages
	highlight_package_json()

	local count = vim.tbl_count(packages)
	vim.notify(string.format("Highlighted %d outdated npm packages in files", count), vim.log.levels.INFO)
end

-- === AUTO-HIGHLIGHTING SETUP ===

-- Auto-highlight when files are opened or changed
local function setup_auto_highlighting()
	local group = vim.api.nvim_create_augroup("OutdatedPackageHighlight", { clear = true })

	-- Clear caches when buffers change
	vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout" }, {
		group = group,
		callback = clear_caches,
	})

	-- Python files - only rebuild cache if needed
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = "requirements.txt",
		callback = function()
			clear_caches()
			M.python_highlight()
		end,
	})

	-- Go files
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = "go.mod",
		callback = function()
			clear_caches()
			M.go_highlight()
		end,
	})

	-- npm files
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = "package.json",
		callback = function()
			clear_caches()
			M.npm_highlight()
		end,
	})
end

-- Initialize auto-highlighting
function M.setup()
	setup_auto_highlighting()
end

function M.refresh_cache()
	clear_caches()
	rebuild_buffer_cache()
end

-- Clear all highlights (useful for cleanup)
function M.clear_all_highlights()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		clear_highlights(bufnr)
	end
	outdated_packages = {}
end

return M
