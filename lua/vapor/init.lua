local M = {}

local defaults = {
    slots = 9,
    storage_path = nil,
    map_slots = true,
    legacy_commands = true,
    alt_chars = { "¡", "™", "£", "¢", "∞", "§", "¶", "•", "ª" },
}

local config = {}

---@type table<number, { path: string, kind: "dir"|"file" }>
local favorites = {}

local configured = false

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "Vapor" })
end

-- Buffer names can contain shell-style escaping ("a\\ b"). Vapor stores real
-- filesystem paths so Oil and Telescope receive paths without literal slashes.
local function unescape(path)
    return (path:gsub("\\(.)", "%1"))
end

local function ensure_setup()
    if not configured then
        M.setup()
    end
end

function M.load()
    favorites = {}

    local fd = io.open(config.storage_path, "r")
    if not fd then
        return favorites
    end

    local content = fd:read("*a")
    fd:close()

    local ok, decoded = pcall(vim.json.decode, content)
    if not ok or type(decoded) ~= "table" then
        notify("could not read " .. config.storage_path, vim.log.levels.WARN)
        return favorites
    end

    -- An object keyed by slot preserves empty slots; a JSON array would close
    -- the gaps and destroy the fixed numbers used for muscle memory.
    for slot = 1, config.slots do
        local entry = decoded[tostring(slot)]
        if type(entry) == "table" and type(entry.path) == "string" then
            favorites[slot] = {
                path = unescape(entry.path),
                kind = entry.kind == "file" and "file" or "dir",
            }
        end
    end

    return favorites
end

function M.save()
    ensure_setup()

    local parent = vim.fn.fnamemodify(config.storage_path, ":h")
    if vim.fn.isdirectory(parent) == 0 then
        vim.fn.mkdir(parent, "p")
    end

    local out = {}
    for slot, entry in pairs(favorites) do
        out[tostring(slot)] = entry
    end

    local fd = io.open(config.storage_path, "w")
    if not fd then
        notify("cannot write " .. config.storage_path, vim.log.levels.ERROR)
        return false
    end

    fd:write(vim.json.encode(out))
    fd:close()
    return true
end

-- Resolve what the current buffer represents: a regular file, an Oil
-- directory, or the current working directory for dashboards and terminals.
local function current_target(force_dir)
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)

    local oil_path = name:match("^oil://(.*)$")
    if oil_path then
        return {
            path = unescape(vim.fn.fnamemodify(oil_path, ":p:h")),
            kind = "dir",
        }
    end

    if
        not force_dir
        and name ~= ""
        and vim.bo[buf].buftype == ""
        and vim.fn.filereadable(name) == 1
    then
        return { path = vim.fn.fnamemodify(name, ":p"), kind = "file" }
    end

    return { path = vim.fn.getcwd(), kind = "dir" }
end

local function git_root(dir)
    local git = vim.fs.find(".git", { path = dir, upward = true })[1]
    return git and vim.fn.fnamemodify(git, ":h") or dir
end

local function slot_arg(value, required)
    local slot = tonumber(value)

    if not slot or slot < 1 or slot > config.slots or slot % 1 ~= 0 then
        if value ~= "" or required then
            notify(
                "slot must be 1-" .. config.slots,
                vim.log.levels.ERROR
            )
            return nil, false
        end
        return nil, true
    end

    return slot, true
end

function M.open(slot)
    ensure_setup()

    local entry = favorites[slot]
    if not entry then
        notify("slot " .. slot .. " is empty", vim.log.levels.WARN)
        return
    end

    if entry.kind == "dir" then
        if vim.fn.isdirectory(entry.path) == 0 then
            notify("missing directory " .. entry.path, vim.log.levels.ERROR)
            return
        end

        vim.cmd.cd(vim.fn.fnameescape(entry.path))

        -- Oil is optional for other users. Ivan's setup has it installed, so
        -- favorited folders open as editable directory buffers; otherwise a
        -- normal directory buffer is a safe fallback.
        local ok, oil = pcall(require, "oil")
        if ok then
            oil.open(entry.path)
        else
            vim.cmd.edit(vim.fn.fnameescape(entry.path))
        end
        return
    end

    if vim.fn.filereadable(entry.path) == 0 then
        notify("missing file " .. entry.path, vim.log.levels.ERROR)
        return
    end

    -- Schedule file opening so swap-file prompts can be answered normally
    -- when Vapor is called from a keymap or dashboard callback.
    vim.schedule(function()
        local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(entry.path))
        if not ok then
            notify(
                vim.trim(tostring(err):gsub("^[^:]*:%d+: ", "")),
                vim.log.levels.WARN
            )
            return
        end

        -- Scope Telescope and other project tools to this file's repository
        -- without changing Neovim's process-wide working directory.
        local root = git_root(vim.fn.fnamemodify(entry.path, ":h"))
        vim.cmd.lcd(vim.fn.fnameescape(root))
    end)
end

function M.add(slot, force_dir)
    ensure_setup()

    local entry = current_target(force_dir)

    if not slot then
        -- Adding an existing target retains its current slot.
        for candidate = 1, config.slots do
            local existing = favorites[candidate]
            if existing and existing.path == entry.path then
                slot = candidate
                break
            end
        end
    end

    if not slot then
        for candidate = 1, config.slots do
            if not favorites[candidate] then
                slot = candidate
                break
            end
        end
    end

    if not slot then
        notify(
            "all "
                .. config.slots
                .. " slots are taken; use :VprFav <slot> to overwrite",
            vim.log.levels.ERROR
        )
        return
    end

    favorites[slot] = entry
    if M.save() then
        notify(("%d → %s"):format(slot, vim.fn.fnamemodify(entry.path, ":~")))
    end
end

function M.remove(slot)
    ensure_setup()

    if not favorites[slot] then
        notify("slot " .. slot .. " is already empty", vim.log.levels.WARN)
        return
    end

    favorites[slot] = nil
    if M.save() then
        notify("cleared slot " .. slot)
    end
end

function M.lines()
    ensure_setup()

    local lines = {}
    for slot = 1, config.slots do
        local entry = favorites[slot]
        lines[#lines + 1] = ("%d  %s"):format(
            slot,
            entry and vim.fn.fnamemodify(entry.path, ":~") or "—"
        )
    end
    return lines
end

-- Open Telescope at a favorite's directory or project root. With no slot,
-- search from the current effective working directory.
function M.find(slot)
    ensure_setup()

    local cwd = vim.fn.getcwd()
    if slot then
        local entry = favorites[slot]
        if not entry then
            notify("slot " .. slot .. " is empty", vim.log.levels.WARN)
            return
        end
        cwd = entry.kind == "dir"
                and entry.path
            or git_root(vim.fn.fnamemodify(entry.path, ":h"))
    end

    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then
        notify("Telescope is not installed", vim.log.levels.ERROR)
        return
    end

    telescope.find_files({ cwd = cwd })
end

-- Snacks dashboard section: only occupied slots are rendered, and the
-- Option-number labels do not consume the dashboard's plain numeric keys.
function M.dashboard_items()
    ensure_setup()
    M.load()

    local items = {}
    for slot = 1, config.slots do
        local entry = favorites[slot]
        if entry then
            items[#items + 1] = {
                file = entry.path,
                icon = entry.kind == "dir" and "directory" or "file",
                key = "<M-" .. slot .. ">",
                label = "⌥" .. slot,
                action = function()
                    M.open(slot)
                end,
            }
        end
    end

    if #items == 0 then
        items[1] = {
            icon = " ",
            desc = "none yet — :VprFav pins the current file or folder",
        }
    end

    return items
end

local function create_commands()
    local function add_command(cmd)
        local slot, ok = slot_arg(cmd.args, false)
        if ok then
            M.add(slot, cmd.bang)
        end
    end

    local function delete_command(cmd)
        local slot, ok = slot_arg(cmd.args, true)
        if ok and slot then
            M.remove(slot)
        end
    end

    local function list_command()
        M.load()
        notify(table.concat(M.lines(), "\n"))
    end

    local function find_command(cmd)
        local slot, ok = slot_arg(cmd.args, false)
        if ok then
            M.find(slot)
        end
    end

    vim.api.nvim_create_user_command("VprFav", add_command, {
        nargs = "?",
        bang = true,
        force = true,
        desc = "Pin the current file (! or no file: cwd) in Vapor",
    })
    vim.api.nvim_create_user_command("VprDel", delete_command, {
        nargs = 1,
        force = true,
        desc = "Clear a Vapor slot",
    })
    vim.api.nvim_create_user_command("VprLS", list_command, {
        force = true,
        desc = "List Vapor slots",
    })
    vim.api.nvim_create_user_command("VprF", find_command, {
        nargs = "?",
        force = true,
        desc = "Find files with Telescope from a Vapor slot",
    })

    if config.legacy_commands then
        vim.api.nvim_create_user_command("Fav", add_command, {
            nargs = "?",
            bang = true,
            force = true,
            desc = "Alias for :VprFav",
        })
        vim.api.nvim_create_user_command("FavDel", delete_command, {
            nargs = 1,
            force = true,
            desc = "Alias for :VprDel",
        })
        vim.api.nvim_create_user_command("FavList", list_command, {
            force = true,
            desc = "Alias for :VprLS",
        })
    end
end

local function create_keymaps()
    if not config.map_slots then
        return
    end

    for slot = 1, config.slots do
        local open = function()
            M.open(slot)
        end
        local opts = { desc = "Vapor slot " .. slot }

        -- Terminals may encode Alt/Option-number as either Meta-number or a
        -- composed character. Map both forms for portable shortcuts.
        vim.keymap.set("n", "<M-" .. slot .. ">", open, opts)
        if config.alt_chars[slot] then
            vim.keymap.set("n", config.alt_chars[slot], open, opts)
        end
    end
end

function M.setup(opts)
    config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
    config.storage_path = config.storage_path
        or vim.env.NVIM_FAVORITES_FILE
        or (vim.fn.stdpath("config") .. "/favorites.json")

    configured = true
    M.load()
    create_commands()
    create_keymaps()

    return M
end

return M
