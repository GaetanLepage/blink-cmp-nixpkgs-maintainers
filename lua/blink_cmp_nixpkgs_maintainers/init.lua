local maintainers = require("blink_cmp_nixpkgs_maintainers.maintainers")
local types = require("blink.cmp.types")

---@class blink_cmp_nixpkgs_maintainers.Option
---@field public cache_lifetime integer
---@field public silent boolean
---@field public nixpkgs_flake_uri string

---@type blink_cmp_nixpkgs_maintainers.Option
local defaults = {
    cache_lifetime = 14,
    silent = false,
    nixpkgs_flake_uri = "nixpkgs",
}

---@param opts blink_cmp_nixpkgs_maintainers.Option|nil
---@return blink_cmp_nixpkgs_maintainers.Option
local function validate_option(opts)
    opts = vim.tbl_deep_extend("force", defaults, opts or {})
    vim.validate(
        "blink-cmp-nixpkgs-maintainers.cache_lifetime",
        opts.cache_lifetime,
        "number"
    )
    vim.validate(
        "blink-cmp-nixpkgs-maintainers.silent",
        opts.silent,
        "boolean"
    )
    vim.validate(
        "blink-cmp-nixpkgs-maintainers.nixpkgs_flake_uri",
        opts.nixpkgs_flake_uri,
        "string"
    )
    return opts
end

---@class blink.cmp.Source
local source = {}

-- blink.cmp will call require('...').new(opts)
function source.new(opts)
    local self = setmetatable({}, { __index = source })
    self.opts = validate_option(opts)

    maintainers.silent = self.opts.silent
    maintainers.cache_lifetime_days = self.opts.cache_lifetime
    maintainers.nixpkgs_flake_uri = self.opts.nixpkgs_flake_uri
    maintainers.refresh_cache_if_needed()

    return self
end

-- Only enable when editing PR descriptions (i.e. markdown files located in /tmp or /private/var)
function source:enabled()
    if vim.bo.filetype ~= "markdown" then
        return false
    end

    local filepath = vim.fn.expand("%:p")
    local is_in_linux_tmp = vim.startswith(filepath, "/tmp")
    local is_in_darwin_tmp = vim.startswith(filepath, "/private/var/")

    return is_in_linux_tmp or is_in_darwin_tmp
end

function source:get_trigger_characters()
    return { "@" }
end

-- ctx has keyword/cursor/bufnr etc, but we can compute robustly from buffer+cursor too.
function source:get_completions(ctx, callback)
    local cursor_row = ctx.cursor[1]
    local cursor_col = ctx.cursor[2]
    local start_col = ctx.bounds.start_col

    -- "cc @Joh"
    local line = ctx.line
    -- "cc @"
    local prefix = line:sub(1, start_col - 1)
    -- "@Joh"
    local input = line:sub(start_col - 1)

    -- Stop early if necessary
    local should_trigger = (
        vim.startswith(input, "@")
        and (prefix == "@" or vim.endswith(prefix, " @"))
    )

    if not should_trigger then return end

    local maintainers_table = maintainers.get_cached_maintainers()

    ---@type lsp.CompletionItem[]
    local items = {}
    for alias, github_handle in pairs(maintainers_table) do
        local gh = tostring(github_handle or "")
        if gh ~= "" then
            table.insert(items, {
                label = string.format("%s (@%s)", alias, gh),
                kind = types.CompletionItemKind.Text,
                filterText = ("@" .. gh .. " " .. alias),
                textEdit = {
                    newText = "@" .. gh,
                    range = {
                        start = {
                            line = cursor_row - 1,
                            character = start_col - 2
                        },
                        ["end"] = {
                            line = cursor_row - 1,
                            character = cursor_col
                        },
                    },
                },
            })
        end
    end

    callback({
        items = items,
        -- keep requesting as user types/deletes after '@'
        is_incomplete_forward = true,
        is_incomplete_backward = true,
    })
end

return source
