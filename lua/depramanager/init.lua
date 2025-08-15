local M = {}
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local uv = vim.loop

local function setup_highlights()
	vim.api.nvim_set_hl(0, "OutdatedVersion", { fg = "#f38ba8", bg = "#45475a", bold = true })
	vim.api.nvim_set_hl(0, "OutdatedVersionText", { fg = "#6c7086", italic = true })
	vim.api.nvim_set_hl(0, "AvailableVersion", { fg = "#a6e3a1", italic = true, bold = true })
	vim.api.nvim_set_hl(0, "LoadingIndicator", { fg = "#fab387", italic = true })
	vim.api.nvim_set_hl(0, "ErrorIndicator", { fg = "#f38ba8", bold = true })
end

local outdated_packages = {}
local loading_states = {}

local function add_virtual_text(bufnr, line_num, current_version, available_version)
	local ns_id = vim.api.nvim_create_namespace("outdated_versions")
	local virt_text = string.format("  → %s available", available_version)
	vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num, 0, {
		virt_text = { { virt_text, "AvailableVersion" } },
		virt_text_pos = "eol",
		priority = 100,
	})
end

local function highlight_version_in_buffer(bufnr, line_num, line_content, package_name, current_version)
	local ns_id = vim.api.nvim_create_namespace("outdated_versions")
	local version_start, version_end = line_content:find(vim.pesc(current_version))
	if version_start then
		vim.api.nvim_buf_add_highlight(bufnr, ns_id, "OutdatedVersion", line_num, version_start - 1, version_end)
	end
end

local function clear_highlights(bufnr)
	local ns_id = vim.api.nvim_create_namespace("outdated_versions")
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

local file_patterns = {
	python = { "requirements%.txt$" },
	go = { "go%.mod$" },
	npm = { "package%.json$" },
	php = { "composer%.json$" },
	rust = { "Cargo%.toml$" },
}

local function rebuild_buffer_cache()
	buffer_cache = { python = {}, go = {}, npm = {}, php = {}, rust = {} }
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local buf_name = vim.api.nvim_buf_get_name(bufnr)
			if buf_name and buf_name ~= "" then
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

local file_exists_cache = {}
local function file_exists_cached(filepath)
	if file_exists_cache[filepath] == nil then
		file_exists_cache[filepath] = vim.fn.filereadable(filepath) == 1
	end
	return file_exists_cache[filepath]
end

local function clear_caches()
	buffer_cache = {}
	file_exists_cache = {}
end

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
			local package_pattern = "^([%w%-_%.]+)[=<>~!]+([%d%.%w%-%.]+)"
			for line_num, line_content in ipairs(lines) do
				if line_content ~= "" and not line_content:match("^%s*#") then
					local package, version = line_content:match(package_pattern)
					if package and version and outdated_packages.python and outdated_packages.python[package] then
						line_num = line_num - 1
						highlight_version_in_buffer(bufnr, line_num, line_content, package, version)
						add_virtual_text(bufnr, line_num, version, outdated_packages.python[package])
					end
				end
			end
		end
		::continue::
	end
end

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
		local module_pattern = "^%s*([%w%.%-_/]+)%s+v([%d%.%w%-%.]+)"
		for line_num, line_content in ipairs(lines) do
			if line_content ~= "" and not line_content:match("^%s*//") then
				local module, version = line_content:match(module_pattern)
				if module and version and outdated_packages.go and outdated_packages.go[module] then
					line_num = line_num - 1
					local full_version = "v" .. version
					highlight_version_in_buffer(bufnr, line_num, line_content, module, full_version)
					add_virtual_text(bufnr, line_num, full_version, outdated_packages.go[module])
				end
			end
		end
		::continue::
	end
end

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
		local package_pattern = '"([%w%-@/]+)"%s*:%s*"[%^~]?([%d%.%w%-]+)"'
		local in_deps_section = false
		for line_num, line_content in ipairs(lines) do
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
					line_num = line_num - 1
					highlight_version_in_buffer(bufnr, line_num, line_content, package, version)
					add_virtual_text(bufnr, line_num, version, outdated_packages.npm[package])
				end
			end
			::continue_line::
		end
		::continue::
	end
end

local function highlight_composer_json()
	if not buffer_cache.php then
		rebuild_buffer_cache()
	end
	for _, buf_info in ipairs(buffer_cache.php) do
		local bufnr = buf_info.bufnr
		local filepath = vim.fn.getcwd() .. "/composer.json"
		if not file_exists_cached(filepath) then
			goto continue
		end
		clear_highlights(bufnr)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local package_pattern = '"([%w%-_/]+)"%s*:%s*"[%^~]?([%d%.%w%-]+)"'
		local in_deps_section = false
		for line_num, line_content in ipairs(lines) do
			if line_content:match('"require"') or line_content:match('"require%-dev"') then
				in_deps_section = true
				goto continue_line
			elseif line_content:match("^%s*}") then
				in_deps_section = false
				goto continue_line
			end
			if in_deps_section and line_content ~= "" then
				local package, version = line_content:match(package_pattern)
				if package and version and outdated_packages.php and outdated_packages.php[package] then
					line_num = line_num - 1
					highlight_version_in_buffer(bufnr, line_num, line_content, package, version)
					add_virtual_text(bufnr, line_num, version, outdated_packages.php[package])
				end
			end
			::continue_line::
		end
		::continue::
	end
end

local function highlight_cargo_toml()
	if not buffer_cache.rust then
		rebuild_buffer_cache()
	end
	for _, buf_info in ipairs(buffer_cache.rust) do
		local bufnr = buf_info.bufnr
		local filepath = vim.fn.getcwd() .. "/Cargo.toml"
		if not file_exists_cached(filepath) then
			goto continue
		end
		clear_highlights(bufnr)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local package_pattern = '^([%w%-_]+)%s*=%s*"([%d%.%w%-%.]+)"'
		local in_deps_section = false
		for line_num, line_content in ipairs(lines) do
			if line_content:match("^%[dependencies%]") or line_content:match("^%[dev%-dependencies%]") then
				in_deps_section = true
				goto continue_line
			elseif line_content:match("^%[") then
				in_deps_section = false
				goto continue_line
			end
			if in_deps_section and line_content ~= "" and not line_content:match("^%s*#") then
				local package, version = line_content:match(package_pattern)
				if package and version and outdated_packages.rust and outdated_packages.rust[package] then
					line_num = line_num - 1
					highlight_version_in_buffer(bufnr, line_num, line_content, package, version)
					add_virtual_text(bufnr, line_num, version, outdated_packages.rust[package])
				end
			end
			::continue_line::
		end
		::continue::
	end
end

local function create_enhanced_picker(title, results, lang)
	if #results == 0 then
		vim.notify("✅ No results to display", vim.log.levels.INFO)
		return
	end
	pickers
		.new({}, {
			prompt_title = title,
			finder = finders.new_table({ results = results }),
			sorter = conf.generic_sorter({}),
			previewer = false,
			layout_config = {
				height = math.min(#results + 5, 20),
				width = 0.8,
			},
			attach_mappings = function(prompt_bufnr, map)
				map("i", "<CR>", function()
					local selection = action_state.get_selected_entry()
					if not selection then
						vim.notify("No selection made", vim.log.levels.WARN)
						return
					end
					actions.close(prompt_bufnr)
					vim.notify("📋 Copied to clipboard: " .. selection[1], vim.log.levels.INFO)
					vim.fn.setreg("+", selection[1])
				end)
				map("i", "<C-r>", function()
					actions.close(prompt_bufnr)
					if lang == "python" then
						M.python_telescope()
					elseif lang == "go" then
						M.go_telescope()
					elseif lang == "npm" then
						M.npm_telescope()
					elseif lang == "php" then
						M.php_telescope()
					elseif lang == "rust" then
						M.rust_telescope()
					end
				end)
				return true
			end,
		})
		:find()
end

local function run_command_async(cmd, callback)
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)
	local stdout_data = {}
	local stderr_data = {}
	local handle
	handle = uv.spawn("sh", {
		args = { "-c", cmd },
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		stdout:read_stop()
		stderr:read_stop()
		stdout:close()
		stderr:close()
		handle:close()
		vim.schedule(function()
			callback(code, stdout_data, stderr_data)
		end)
	end)
	if not handle then
		callback(1, {}, { "Failed to spawn process" })
		return
	end
	stdout:read_start(function(err, data)
		if err then
			table.insert(stderr_data, err)
		elseif data then
			table.insert(stdout_data, data)
		end
	end)
	stderr:read_start(function(err, data)
		if err then
			table.insert(stderr_data, err)
		elseif data then
			table.insert(stderr_data, data)
		end
	end)
end

local function get_python_outdated_async(callback)
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
			callback(nil, "No Python executable found")
			return
		end
		python = system_python
	end
	local cmd = python .. " -m pip list --outdated --format=columns"
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 then
			local error_msg = table.concat(stderr_data, "")
			if error_msg == "" then
				error_msg = table.concat(stdout_data, "")
			end
			callback(nil, "pip list --outdated failed: " .. (error_msg or "unknown error"))
			return
		end
		local results = vim.split(table.concat(stdout_data, ""), "\n")
		if #results <= 2 then
			callback({}, nil, {})
			return
		end
		local packages = {}
		local display_results = {}
		for i = 3, #results do
			local line = results[i]
			if line and line:match("%S") then
				local package, current, available = line:match("^(%S+)%s+(%S+)%s+(%S+)")
				if package and current and available then
					packages[package] = available
					table.insert(display_results, string.format("📦 %s: %s → %s", package, current, available))
				end
			end
		end
		callback(packages, nil, display_results)
	end)
end

local function get_go_outdated_async(callback)
	local cmd = "go list -m -u all"
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 then
			local error_msg = table.concat(stderr_data, "")
			callback(nil, "Go command failed: " .. (error_msg or "unknown error"))
			return
		end
		local results = vim.split(table.concat(stdout_data, ""), "\n")
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
						table.insert(display_results, string.format("🚀 %s: %s → %s", module, current, available))
					end
				end
			end
		end
		callback(packages, nil, display_results)
	end)
end

local function get_npm_outdated_async(callback)
	local cwd = vim.fn.getcwd()
	if not vim.fn.filereadable(cwd .. "/package.json") then
		callback(nil, "No package.json found in project")
		return
	end
	if not vim.fn.isdirectory(cwd .. "/node_modules") then
		callback(nil, "No node_modules/ found — run `npm install` first")
		return
	end
	local cmd = "npm outdated --depth=0 --color=false"
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		local results = vim.split(table.concat(stdout_data, ""), "\n")
		if #results == 0 then
			if code ~= 0 then
				local error_msg = table.concat(stderr_data, "")
				callback(nil, "npm outdated failed: " .. (error_msg or "unknown error"))
			else
				callback({}, nil, {})
			end
			return
		end
		local packages = {}
		local display_results = {}
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
					table.insert(display_results, string.format("📦 %s: %s → %s", package, current, available))
				end
			end
		end
		callback(packages, nil, display_results)
	end)
end

local function get_php_outdated_async(callback)
	local cwd = vim.fn.getcwd()
	if not vim.fn.filereadable(cwd .. "/composer.json") then
		callback(nil, "No composer.json found in project")
		return
	end
	local composer_path = vim.fn.exepath("composer")
	if not composer_path then
		callback(nil, "Composer not found. Please install Composer: https://getcomposer.org")
		return
	end
	local cmd = "composer outdated --format=json --direct"
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 then
			local error_msg = table.concat(stderr_data, "")
			callback(nil, "Composer outdated failed: " .. (error_msg or "unknown error"))
			return
		end
		local json_str = table.concat(stdout_data, "")
		if json_str == "" or json_str == "[]" then
			callback({}, nil, {})
			return
		end
		local packages = {}
		local display_results = {}
		-- Parse JSON-like output from composer outdated
		for package_block in json_str:gmatch('"name":%s*"([^"]+)".-"version":%s*"([^"]+)".-"latest":%s*"([^"]+)"') do
			local name, current, latest = package_block:match("([^,]+),([^,]+),(.+)")
			if name and current and latest then
				packages[name] = latest
				table.insert(display_results, string.format("🐘 %s: %s → %s", name, current, latest))
			end
		end
		-- Fallback to plain text parsing if JSON parsing fails
		if vim.tbl_isempty(packages) then
			local lines = vim.split(json_str, "\n")
			for _, line in ipairs(lines) do
				local name, current, latest = line:match("^(%S+)%s+(%S+)%s+(%S+)")
				if name and current and latest and name ~= "Name" then
					packages[name] = latest
					table.insert(display_results, string.format("🐘 %s: %s → %s", name, current, latest))
				end
			end
		end
		callback(packages, nil, display_results)
	end)
end

local function get_rust_outdated_async(callback)
	local cwd = vim.fn.getcwd()
	if not vim.fn.filereadable(cwd .. "/Cargo.toml") then
		callback(nil, "No Cargo.toml found in project")
		return
	end
	local cargo_path = vim.fn.exepath("cargo")
	if not cargo_path then
		callback(nil, "Cargo not found. Please install Rust: https://rustup.rs/")
		return
	end
	-- Use cargo-outdated if available, otherwise provide helpful message
	local cargo_outdated_path = vim.fn.exepath("cargo-outdated")
	local cmd
	if cargo_outdated_path then
		cmd = "cargo outdated --format=json"
	else
		callback(nil, "For best results, install cargo-outdated: cargo install cargo-outdated")
		return
	end

	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 then
			local error_msg = table.concat(stderr_data, "")
			callback(nil, "Cargo outdated failed: " .. (error_msg or "unknown error"))
			return
		end
		local output = table.concat(stdout_data, "")
		local packages = {}
		local display_results = {}

		-- Parse JSON output from cargo-outdated
		for crate_block in output:gmatch('"name":%s*"([^"]+)".-"project":%s*"([^"]+)".-"latest":%s*"([^"]+)"') do
			local name, current, latest = crate_block:match("([^,]+),([^,]+),(.+)")
			if name and current and latest and current ~= latest then
				packages[name] = latest
				table.insert(display_results, string.format("🦀 %s: %s → %s", name, current, latest))
			end
		end

		callback(packages, nil, display_results)
	end)
end

local function get_python_vulnerabilities_async(callback)
	local safety_path = vim.fn.exepath("safety")
	if not safety_path or safety_path == "" or not uv.fs_stat(safety_path) then
		callback(nil, "Safety tool not found. Install it with: pip install safety")
		return
	end
	local cmd = safety_path .. " check --json"
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 then
			local error_msg = table.concat(stderr_data, "")
			callback(nil, "Safety scan failed: " .. (error_msg or "unknown error"))
			return
		end
		local json_str = table.concat(stdout_data, "")
		if json_str == "" or json_str == "[]" then
			callback({}, nil, {})
			return
		end
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
					"🔒 [%s] %s: %s - %s...",
					packages[package_name].severity:upper(),
					package_name,
					vuln_id,
					advisory:sub(1, 80)
				)
			)
		end
		callback(packages, nil, display_results)
	end)
end

local function get_go_vulnerabilities_async(callback)
	local govuln_check = vim.fn.exepath("govulncheck")
	if not govuln_check then
		callback(nil, "govulncheck not found. Install with: go install golang.org/x/vuln/cmd/govulncheck@latest")
		return
	end
	local cmd = "govulncheck -json ./..."
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 then
			local error_msg = table.concat(stderr_data, "")
			callback(nil, "govulncheck scan failed: " .. (error_msg or "unknown error"))
			return
		end
		local packages = {}
		local display_results = {}
		local output = table.concat(stdout_data, "")
		for line in output:gmatch("[^\n]+") do
			if line:match('"finding"') then
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
							"🔒 [%s] %s: %s - %s",
							packages[module].severity:upper(),
							module,
							vuln_id,
							(summary or "No summary"):sub(1, 80) .. "..."
						)
					)
				end
			end
		end
		callback(packages, nil, display_results)
	end)
end

local function get_php_vulnerabilities_async(callback)
	local cwd = vim.fn.getcwd()
	if not vim.fn.filereadable(cwd .. "/composer.json") then
		callback(nil, "No composer.json found in project")
		return
	end
	local cmd = "composer audit --format=json"
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 then
			local error_msg = table.concat(stderr_data, "")
			callback(nil, "Composer audit failed: " .. (error_msg or "unknown error"))
			return
		end
		local json_str = table.concat(stdout_data, "")
		if json_str == "" or json_str == "[]" then
			callback({}, nil, {})
			return
		end
		local packages = {}
		local display_results = {}
		-- Parse vulnerabilities from composer audit
		for vuln_match in json_str:gmatch('"package":%s*"([^"]+)".-"title":%s*"([^"]+)".-"severity":%s*"([^"]+)"') do
			local package_name, title, severity = vuln_match:match("([^,]+),([^,]+),(.+)")
			if package_name and title and severity then
				if not packages[package_name] then
					packages[package_name] = { severity = severity, count = 0, vulns = {} }
				end
				packages[package_name].count = packages[package_name].count + 1
				table.insert(packages[package_name].vulns, { title = title })
				table.insert(
					display_results,
					string.format("🔒 [%s] %s: %s", severity:upper(), package_name, title:sub(1, 80) .. "...")
				)
			end
		end
		callback(packages, nil, display_results)
	end)
end

local function get_rust_vulnerabilities_async(callback)
	local cwd = vim.fn.getcwd()
	if not vim.fn.filereadable(cwd .. "/Cargo.toml") then
		callback(nil, "No Cargo.toml found in project")
		return
	end
	local cargo_audit_path = vim.fn.exepath("cargo-audit")
	if not cargo_audit_path then
		callback(nil, "cargo-audit not found. Install with: cargo install cargo-audit")
		return
	end
	local cmd = "cargo audit --json"
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 then
			local error_msg = table.concat(stderr_data, "")
			callback(nil, "cargo audit failed: " .. (error_msg or "unknown error"))
			return
		end
		local json_str = table.concat(stdout_data, "")
		if json_str == "" then
			callback({}, nil, {})
			return
		end
		local packages = {}
		local display_results = {}
		-- Parse vulnerabilities from cargo audit
		for vuln_match in json_str:gmatch('"package":%s*"([^"]+)".-"title":%s*"([^"]+)".-"severity":%s*"([^"]+)"') do
			local package_name, title, severity = vuln_match:match("([^,]+),([^,]+),(.+)")
			if package_name and title and severity then
				if not packages[package_name] then
					packages[package_name] = { severity = severity, count = 0, vulns = {} }
				end
				packages[package_name].count = packages[package_name].count + 1
				table.insert(packages[package_name].vulns, { title = title })
				table.insert(
					display_results,
					string.format("🔒 [%s] %s: %s", severity:upper(), package_name, title:sub(1, 80) .. "...")
				)
			end
		end
		callback(packages, nil, display_results)
	end)
end

local function get_npm_vulnerabilities_async(callback)
	local cwd = vim.fn.getcwd()
	if not vim.fn.filereadable(cwd .. "/package.json") then
		callback(nil, "No package.json found in project")
		return
	end
	local cmd = "npm audit --json"
	run_command_async(cmd, function(code, stdout_data, stderr_data)
		if code ~= 0 and code ~= 1 then
			local error_msg = table.concat(stderr_data, "")
			callback(nil, "npm audit failed: " .. (error_msg or "unknown error"))
			return
		end
		local json_str = table.concat(stdout_data, "")
		if json_str == "" then
			callback({}, nil, {})
			return
		end
		local packages = {}
		local display_results = {}
		for vuln_match in json_str:gmatch('"module_name":%s*"([^"]+)".-"severity":%s*"([^"]+)".-"title":%s*"([^"]+)"') do
			local package_name, severity, title = vuln_match:match("([^,]+),([^,]+),(.+)")
			if package_name and severity and title then
				if not packages[package_name] then
					packages[package_name] = { severity = severity, count = 0, vulns = {} }
				else
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
					string.format("🔒 [%s] %s: %s", severity:upper(), package_name, title:sub(1, 100) .. "...")
				)
			end
		end
		callback(packages, nil, display_results)
	end)
end

function M.python_telescope()
	vim.notify("🔍 Checking Python dependencies...", vim.log.levels.INFO)
	get_python_outdated_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No outdated Python packages", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("📦 Outdated Python Packages", display_results, "python")
	end)
end

function M.go_telescope()
	vim.notify("🔍 Checking Go modules...", vim.log.levels.INFO)
	get_go_outdated_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No outdated Go modules", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("🚀 Outdated Go Modules", display_results, "go")
	end)
end

function M.npm_telescope()
	vim.notify("🔍 Checking npm packages...", vim.log.levels.INFO)
	get_npm_outdated_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No outdated npm packages", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("📦 Outdated npm Packages", display_results, "npm")
	end)
end

function M.php_telescope()
	vim.notify("🔍 Checking PHP dependencies...", vim.log.levels.INFO)
	get_php_outdated_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No outdated PHP packages", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("🐘 Outdated PHP Packages", display_results, "php")
	end)
end

function M.rust_telescope()
	vim.notify("🔍 Checking Rust dependencies...", vim.log.levels.INFO)
	get_rust_outdated_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No outdated Rust crates", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("🦀 Outdated Rust Crates", display_results, "rust")
	end)
end

function M.python_vulnerabilities_telescope()
	vim.notify("🔒 Scanning Python vulnerabilities...", vim.log.levels.INFO)
	get_python_vulnerabilities_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No Python vulnerabilities found", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("🔒 Python Security Vulnerabilities", display_results, "python-vuln")
	end)
end

function M.go_vulnerabilities_telescope()
	vim.notify("🔒 Scanning Go vulnerabilities...", vim.log.levels.INFO)
	get_go_vulnerabilities_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No Go vulnerabilities found", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("🔒 Go Security Vulnerabilities", display_results, "go-vuln")
	end)
end

function M.npm_vulnerabilities_telescope()
	vim.notify("🔒 Scanning npm vulnerabilities...", vim.log.levels.INFO)
	get_npm_vulnerabilities_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No npm vulnerabilities found", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("🔒 npm Security Vulnerabilities", display_results, "npm-vuln")
	end)
end

function M.php_vulnerabilities_telescope()
	vim.notify("🔒 Scanning PHP vulnerabilities...", vim.log.levels.INFO)
	get_php_vulnerabilities_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No PHP vulnerabilities found", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("🔒 PHP Security Vulnerabilities", display_results, "php-vuln")
	end)
end

function M.rust_vulnerabilities_telescope()
	vim.notify("🔒 Scanning Rust vulnerabilities...", vim.log.levels.INFO)
	get_rust_vulnerabilities_async(function(packages, error_msg, display_results)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if #display_results == 0 then
			vim.notify("✅ No Rust vulnerabilities found", vim.log.levels.INFO)
			return
		end
		create_enhanced_picker("🔒 Rust Security Vulnerabilities", display_results, "rust-vuln")
	end)
end

function M.python_highlight()
	setup_highlights()
	rebuild_buffer_cache()
	get_python_outdated_async(function(packages, error_msg)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if not packages or vim.tbl_isempty(packages) then
			vim.notify("✅ No outdated Python packages to highlight", vim.log.levels.INFO)
			return
		end
		outdated_packages.python = packages
		highlight_python_files()
		local count = vim.tbl_count(packages)
		vim.notify(string.format("✨ Highlighted %d outdated Python packages", count), vim.log.levels.INFO)
	end)
end

function M.go_highlight()
	setup_highlights()
	rebuild_buffer_cache()
	get_go_outdated_async(function(packages, error_msg)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if not packages or vim.tbl_isempty(packages) then
			vim.notify("✅ No outdated Go modules to highlight", vim.log.levels.INFO)
			return
		end
		outdated_packages.go = packages
		highlight_go_mod()
		local count = vim.tbl_count(packages)
		vim.notify(string.format("✨ Highlighted %d outdated Go modules", count), vim.log.levels.INFO)
	end)
end

function M.npm_highlight()
	setup_highlights()
	rebuild_buffer_cache()
	get_npm_outdated_async(function(packages, error_msg)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if not packages or vim.tbl_isempty(packages) then
			vim.notify("✅ No outdated npm packages to highlight", vim.log.levels.INFO)
			return
		end
		outdated_packages.npm = packages
		highlight_package_json()
		local count = vim.tbl_count(packages)
		vim.notify(string.format("✨ Highlighted %d outdated npm packages", count), vim.log.levels.INFO)
	end)
end

function M.php_highlight()
	setup_highlights()
	rebuild_buffer_cache()
	get_php_outdated_async(function(packages, error_msg)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if not packages or vim.tbl_isempty(packages) then
			vim.notify("✅ No outdated PHP packages to highlight", vim.log.levels.INFO)
			return
		end
		outdated_packages.php = packages
		highlight_composer_json()
		local count = vim.tbl_count(packages)
		vim.notify(string.format("✨ Highlighted %d outdated PHP packages", count), vim.log.levels.INFO)
	end)
end

function M.rust_highlight()
	setup_highlights()
	rebuild_buffer_cache()
	get_rust_outdated_async(function(packages, error_msg)
		if error_msg then
			vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
			return
		end
		if not packages or vim.tbl_isempty(packages) then
			vim.notify("✅ No outdated Rust crates to highlight", vim.log.levels.INFO)
			return
		end
		outdated_packages.rust = packages
		highlight_cargo_toml()
		local count = vim.tbl_count(packages)
		vim.notify(string.format("✨ Highlighted %d outdated Rust crates", count), vim.log.levels.INFO)
	end)
end

local function setup_auto_highlighting()
	local group = vim.api.nvim_create_augroup("OutdatedPackageHighlight", { clear = true })
	vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout" }, {
		group = group,
		callback = clear_caches,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = "requirements.txt",
		callback = function()
			clear_caches()
			M.python_highlight()
		end,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = "go.mod",
		callback = function()
			clear_caches()
			M.go_highlight()
		end,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = "package.json",
		callback = function()
			clear_caches()
			M.npm_highlight()
		end,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = "composer.json",
		callback = function()
			clear_caches()
			M.php_highlight()
		end,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = "Cargo.toml",
		callback = function()
			clear_caches()
			M.rust_highlight()
		end,
	})
end

function M.setup()
	setup_auto_highlighting()
	setup_highlights()
end

function M.refresh_cache()
	clear_caches()
	rebuild_buffer_cache()
end

function M.clear_all_highlights()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		clear_highlights(bufnr)
	end
	outdated_packages = {}
	loading_states = {}
end

function M.check_all()
	local cwd = vim.fn.getcwd()
	local checks_started = 0
	if vim.fn.filereadable(cwd .. "/requirements.txt") == 1 then
		M.python_highlight()
		checks_started = checks_started + 1
	end
	if vim.fn.filereadable(cwd .. "/go.mod") == 1 then
		M.go_highlight()
		checks_started = checks_started + 1
	end
	if vim.fn.filereadable(cwd .. "/package.json") == 1 then
		M.npm_highlight()
		checks_started = checks_started + 1
	end
	if vim.fn.filereadable(cwd .. "/composer.json") == 1 then
		M.php_highlight()
		checks_started = checks_started + 1
	end
	if vim.fn.filereadable(cwd .. "/Cargo.toml") == 1 then
		M.rust_highlight()
		checks_started = checks_started + 1
	end
	if checks_started == 0 then
		vim.notify("ℹ️  No dependency files found in current project", vim.log.levels.INFO)
	else
		vim.notify(
			string.format("🔍 Started %d dependency check(s) in background", checks_started),
			vim.log.levels.INFO
		)
	end
end

function M.status()
	local status_lines = {}
	local loading_count = 0
	for lang, _ in pairs(loading_states) do
		loading_count = loading_count + 1
		table.insert(status_lines, string.format("🔄 %s: checking...", lang))
	end
	for lang, packages in pairs(outdated_packages) do
		if packages and not vim.tbl_isempty(packages) then
			local count = vim.tbl_count(packages)
			table.insert(status_lines, string.format("📦 %s: %d outdated package(s)", lang, count))
		else
			table.insert(status_lines, string.format("✅ %s: up to date", lang))
		end
	end
	if #status_lines == 0 then
		vim.notify("ℹ️  No dependency checks have been run yet", vim.log.levels.INFO)
	else
		local status_msg = "📊 Dependency Status:\n" .. table.concat(status_lines, "\n")
		vim.notify(status_msg, vim.log.levels.INFO)
	end
end

return M
