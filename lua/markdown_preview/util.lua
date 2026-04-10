-- lua/markdown_preview/util.lua
local M = {}

local sep = package.config:sub(1, 1)

local function dirname(path)
	return path:match("^(.*" .. sep .. ")") or "./"
end

function M.mkdirp(path)
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, "p")
	end
end

function M.file_exists(path)
	if not path then
		return false
	end
	local stat = vim.loop.fs_stat(path)
	return stat and stat.type == "file"
end

function M.write_text(path, text)
	M.mkdirp(dirname(path))
	local fd = assert(vim.loop.fs_open(path, "w", 420)) -- 0644
	assert(vim.loop.fs_write(fd, text, 0))
	assert(vim.loop.fs_close(fd))
end

function M.read_text(path)
	assert(type(path) == "string" and #path > 0, "read_text: path is nil")
	local fd = assert(vim.loop.fs_open(path, "r", 420))
	local stat = assert(vim.loop.fs_fstat(fd))
	local data = assert(vim.loop.fs_read(fd, stat.size, 0))
	assert(vim.loop.fs_close(fd))
	return data
end

function M.copy_file(src, dst)
	assert(type(src) == "string" and #src > 0, "copy_file: source path is nil")
	local data = M.read_text(src)
	M.write_text(dst, data)
end

---Resolve a file shipped with the plugin using runtimepath first.
---@param rel string
---@return string|nil
function M.resolve_asset(rel)
	-- Prefer runtimepath discovery (robust across plugin managers and symlinks)
	local hits = vim.api.nvim_get_runtime_file(rel, false)
	if hits and #hits > 0 then
		return hits[1]
	end

	-- Fallback to path math from this file location
	local info = debug.getinfo(1, "S")
	local this = type(info.source) == "string" and info.source or ""
	if this:sub(1, 1) == "@" then
		this = this:sub(2)
	end
	local root = this:match("(.-)" .. sep .. "lua" .. sep .. "markdown_preview" .. sep .. "util%.lua$")
	if root then
		local candidate = table.concat({ root, rel }, sep)
		if M.file_exists(candidate) then
			return candidate
		end
	end
	return nil
end

function M.open_in_browser(url)
	local cmd
	if vim.fn.has("mac") == 1 then
		cmd = { "open", url }
	elseif vim.fn.has("unix") == 1 then
		cmd = { "xdg-open", url }
	elseif vim.fn.has("win32") == 1 then
		cmd = { "cmd.exe", "/c", "start", url }
	end
	if cmd then
		vim.fn.jobstart(cmd, { detach = true })
	end
end

---Generate a per-buffer workspace directory under Neovim's cache.
---@param bufnr integer
---@return string
function M.workspace_for_buffer(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	local hash = vim.fn.sha256(name):sub(1, 12)
	return vim.fs.joinpath(vim.fn.stdpath("cache"), "markdown-preview", hash)
end

function M.shared_workspace()
	return vim.fs.joinpath(vim.fn.stdpath("cache"), "markdown-preview", "shared")
end

---Return the parent directory of the buffer's file path (absolute).
---@param bufnr integer
---@return string|nil
function M.buf_src_dir(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if not name or name == "" then return nil end
	local abs = vim.fn.fnamemodify(name, ":p:h")
	if abs == "" then return nil end
	return abs
end

---Copy local image files referenced in markdown text into <workspace>/files/
---so the live-server can serve them at /files/<rel_path> without needing to
---follow symlinks that point outside its root directory.
---@param workspace_dir string
---@param src_dir string|nil absolute path to the markdown file's parent directory
---@param text string markdown content to scan for image references
function M.sync_local_images(workspace_dir, src_dir, text)
	if not src_dir or src_dir == "" then return end
	local files_dir = vim.fs.joinpath(workspace_dir, "files")

	-- Remove legacy symlink if present so we can use a real directory
	local lstat = vim.loop.fs_lstat(files_dir)
	if lstat and lstat.type == "link" then
		vim.loop.fs_unlink(files_dir)
		lstat = nil
	end
	if not lstat then
		M.mkdirp(files_dir)
	end

	-- Extract image paths from markdown: ![alt](path) or ![alt](path "title")
	for raw in text:gmatch("!%[.-%]%((.-)%)") do
		local path = raw:match("^(%S+)") or raw
		-- Skip remote/absolute/anchor references
		if path ~= ""
			and not path:match("^https?://")
			and not path:match("^//")
			and not path:match("^data:")
			and not path:match("^/")
			and not path:match("^#")
		then
			local rel = path:gsub("^%./", "")
			local src = vim.fs.joinpath(src_dir, rel)
			local dst = vim.fs.joinpath(files_dir, rel)
			if M.file_exists(src) then
				local src_stat = vim.loop.fs_stat(src)
				local dst_stat = vim.loop.fs_stat(dst)
				-- Only copy if destination is missing or source is newer
				if not dst_stat or (src_stat and src_stat.mtime.sec > dst_stat.mtime.sec) then
					M.mkdirp(dirname(dst))
					-- fs_copyfile handles binary files (images, gifs, etc.) correctly
					vim.loop.fs_copyfile(src, dst)
				end
			end
		end
	end
end

return M
