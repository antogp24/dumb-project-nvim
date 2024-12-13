
-- Global state of the plugin.
-- ----------------------------------------------------------------------------------------------- --

local ctx = {
    this_project_path = nil,
    this_project_config = nil,
    this_project_file_patterns = nil,
    this_project_workspace = nil,
    this_project_build_commands = nil,
    projects_directory = vim.fs.normalize(vim.fn.stdpath('config')) .. '/dumb-project/',
}

-- Default contents of the config file.
-- ----------------------------------------------------------------------------------------------- --

local DEFAULT_CONFIG_STRUCTURE = [[

local project = require('dumb-project')

-- I'm so sorry, this is how pattern matching functions work in lua:
-- https://www.lua.org/manual/5.1/manual.html#5.4.1
-- Function to assist with the most common case:
local function with_ext(ext) return ".*%" .. ext .. "$" end

-- List of accepted file patterns.

file_patterns = {
    with_ext(".c"),
    with_ext(".odin"),
    with_ext(".glsl"),
    with_ext(".bat"),
    with_ext(".sh"),
}

-- List of folders to recursively scan.

workspace = {
    working_dir = "~/dev/project",
    others = {
        "~/libs/library1",
        "~/libs/library2",
        "~/libs/library3",
    },
}

-- List of build commands to use.
-- Each command must be a table{cmdname: string, command: function(returns_string), binding: string}.
-- The require('dumb-project').cmd function assists with creating commands by allowing strings and functions that return strings. 
-- The default working_dir for all commands is the workspace.working_dir.

build_commands = {
    {
        cmdname = "Build",
        command = project.cmd("build.bat"),
        binding = "<F5>",
    },
    {
        cmdname = "RunFile",
        command = project.cmd("odin run ", project.get_current_file, " -file"),
        binding = "<F6>",
    },
    {
        cmdname = "CompileLibrary1",
        command = project.cmd("make && sudo make install"),
        binding = "<F6>",
        working_dir = "~/libs/library1",
    },
}

-- Must call this function to use all the tables defined previously.
project.setup(file_patterns, workspace, build_commands)
]]


-- Helper functions
-- ----------------------------------------------------------------------------------------------- --

local function log_msg(message)
    local log_file = './log.txt'
    local file = io.open(log_file, 'a')

    if file then
        file:write(message .. "\n")
        file:close()
    else
        print("Error: Could not open log file for writing.")
    end
end


local function file_exists(path)
    return vim.loop.fs_stat(path) and vim.loop.fs_stat(path).type == 'file'
end


local function clamp(value, a, b)
    if value < a then return a
    elseif value > b then return b
    else return value end
end


local function table_size(t)
    local count = 0
    for _,_ in ipairs(t) do
        count = count + 1
    end
    return count
end


local function is_filename_valid(filename)
    if string.len(filename) == 0 then return false end
    return not string.match(filename, '[\\/:*?"<>|]')
end


local function create_directory_if_needed(path)
    if vim.fn.isdirectory(path) ~= 1 then
        vim.fn.mkdir(path, 'p')
    end
end


local function validate_file_patterns(file_patterns)
    if type(file_patterns) ~= "table" then
        error("The attribute file_patterns must be a table")
        return false
    end
    for _,v in ipairs(file_patterns) do
        if type(v) ~= "string" then
            error("Expected strings in file_patterns")
            return false
        end
    end
    return true
end


local function validate_workspace(workspace)
    if type(workspace) ~= "table" then
        error("The attribute workspace must be a table")
        return false
    end
    if workspace["working_dir"] == nil or type(workspace["working_dir"]) ~= "string" then
        error([[The table workspace must have an attribute "working_dir", which must be a string.]])
        return false
    end
    if workspace["others"] == nil or type(workspace["others"]) ~= "table" then
        error([[The table workspace must have an attribute "others", which must be a table.]])
        return false
    end
    for _,v in ipairs(workspace["others"]) do
        if type(v) ~= "string" then
            error('Expected strings in workspace["others"].')
            return false
        end
    end
    return true
end


local function validate_build_commands(build_commands, workspace)
    if workspace == nil then return false end

    if type(build_commands) ~= "table" then
        error("The attribute build_commands must be a table")
        return false
    end

    for _,v in ipairs(build_commands) do
        if type(v) ~= "table" then
            error("Expected strings in build_commands")
            return false
        end
        if v["cmdname"] == nil or type(v["cmdname"]) ~= "string" then
            error([[Each command in build commands must have "cmdname", which has to be a string.]])
            return false
        end
        if v["command"] == nil or type(v["command"]) ~= "function" then
            error([[Each command in build commands must have "command", which has to be a function that returns a string.]])
            return false
        end
        if v["binding"] == nil or type(v["binding"]) ~= "string" then
            error([[Each command in build commands must have "binding", which has to be a string.]])
            return false
        end
        if v["working_dir"] == nil then
            v["working_dir"] = workspace.working_dir
        end
    end
    return true
end


local function is_active()
    return ctx.this_project_file_patterns ~= nil and ctx.this_project_workspace ~= nil and ctx.this_project_build_commands ~= nil
end


local function clear_this_project_attribs()
    ctx.this_project_workspace = nil
    ctx.this_project_file_patterns = nil
    ctx.this_project_build_commands = nil
end


local function recursive_open_files_in_dir(dir_name, patterns, in_read_only)
    dir_name = vim.fs.normalize(dir_name)

    local function matches_patterns(filename)
        for _, pattern in ipairs(patterns) do
            if filename:match(pattern) then return true end
        end
        return false
    end

    local function traverse_directory(directory)
        local contents = vim.fn.readdir(directory)
        for _, filename in ipairs(contents) do
            local full_path = directory .. "/" .. filename
            local file_size = vim.fn.getfsize(full_path)

            if vim.fn.isdirectory(full_path) == 1 then
                traverse_directory(full_path)
            elseif matches_patterns(filename) then
                if in_read_only then
                    vim.cmd('view ' .. full_path)
                else
                    vim.cmd('edit ' .. full_path)
                end
            end
        end
    end

    traverse_directory(dir_name)
end


function table_print(t, print_fn, indent)
    if not print_fn then print_fn = print end
    if not indent then indent = 2 end
    local spaces = string.rep(" ", indent)

    print_fn(spaces .. "{")
    for k, v in pairs(t) do
        local formatting = spaces .. spaces .. k .. ": "
        if type(v) == "table" then
            print_fn(formatting)
            table_print(v, print_fn, indent+2)
        else
            print_fn(formatting .. tostring(v))
        end
    end
    print_fn(spaces .. "}")
end

-- API
-- ----------------------------------------------------------------------------------------------- --

local function get_current_file()
    local filepath = vim.fn.expand('%:p')
    return vim.fn.fnamemodify(filepath, ':~')
end


local function open_projects_dir_with_netrw()
    if vim.fn.isdirectory(ctx.projects_directory) == 1 then
        vim.cmd('Explore ' .. ctx.projects_directory)
    else
        print('The directory', ctx.projects_directory, "doesn't exist. Restart neovim.")
    end
end


local function setup(file_patterns, workspace, build_commands)
    clear_this_project_attribs()

    if validate_file_patterns(file_patterns) then
        ctx.this_project_file_patterns = file_patterns
    end
    if validate_workspace(workspace) then
        ctx.this_project_workspace = workspace
    end
    if validate_build_commands(build_commands, ctx.this_project_workspace) then
        ctx.this_project_build_commands = build_commands
    end

    if not is_active() then
        clear_this_project_attribs()
        return false
    end

    -- log_msg("----------------------------------------------")
    -- table_print(ctx.this_project_file_patterns, log_msg)
    -- table_print(ctx.this_project_workspace, log_msg)
    -- table_print(ctx.this_project_build_commands, log_msg)
    -- log_msg("----------------------------------------------")

    return true
end


local function make_build_command(...)
    local num_args = select("#", ...)
    if num_args == 0 then
        error("Expected the function make_build_command to have arguments, but recieved none.")
    end
    local command_args = {}

    for i = 1, num_args do
        local v = select(i, ...)
        if type(v) ~= "string" and type(v) ~= "function" then
            error("Expected strings or functions in require('dumb-project').cmd(...)")
            return nil
        elseif type(v) == "function" and type(v()) ~= "string" then
            error("Functions in require('dumb-project').cmd(...) must return a string.")
            return nil
        end
        table.insert(command_args, v)
    end

    return function()
        local result = ""
        log_msg("INNER: command_args:")
        table_print(command_args, log_msg)
        for _,v in ipairs(command_args) do
            if type(v) == "function" then
                result = result .. v()
            else
                result = result .. v
            end
        end
        return result
    end
end


local function build_command_lister()
    if ctx.this_project_build_commands == nil or table_size(ctx.this_project_build_commands) == 0 then
        print("No available build commands.")
        return
    end

    local command_names = {}
    local corresponding_build_command = {}
    local max_cmdname_length = 0
    local build_commands_count = 0

    for _,v in ipairs(ctx.this_project_build_commands) do
        local cmdname = v["cmdname"]
        local cmdname_length = string.len(cmdname)
        if cmdname_length > max_cmdname_length then
            max_cmdname_length = cmdname_length
        end
        corresponding_build_command[cmdname] = v
        table.insert(command_names, cmdname)
        build_commands_count = build_commands_count + 1
    end

    local TITLE = "Build Commands"
    local terminal_w = vim.o.columns
    local terminal_h = vim.o.lines
    local popup_w = clamp(max_cmdname_length, string.len(TITLE), terminal_w)
    local popup_h = math.min(build_commands_count, terminal_h)
    local popup_x = math.floor((terminal_w - popup_w) / 2)
    local popup_y = math.floor((terminal_h - popup_h) / 2)

    -- Creating title read only window
    local title_buf = vim.api.nvim_create_buf(false, true)
    local title_win = vim.api.nvim_open_win(title_buf, true, {
        relative = 'editor',
        width = popup_w,
        height = 1,
        col = popup_x,
        row = popup_y - 2,
        style = 'minimal',
        border = 'single',
    })
    vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, {TITLE})
    vim.api.nvim_buf_set_option(title_buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(title_buf, 'buftype', 'nofile')

    -- Creating pop-up
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = popup_w,
        height = popup_h,
        col = popup_x,
        row = popup_y,
        style = 'minimal',
        border = 'single',
    })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, command_names)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)

    local current_index = 1

    local function move_up()
        if current_index > 1 then
            current_index = current_index - 1
        else
            current_index = build_commands_count
        end
        vim.api.nvim_win_set_cursor(win, {current_index, 0})
    end

    local function move_down()
        if current_index < build_commands_count then
            current_index = current_index + 1
        else
            current_index = 1
        end
        vim.api.nvim_win_set_cursor(win, {current_index, 0})
    end

    local function close_dialog()
        vim.api.nvim_buf_del_keymap(buf, 'n', '<C-p>')
        vim.api.nvim_buf_del_keymap(buf, 'n', '<C-n>')
        vim.api.nvim_buf_del_keymap(buf, 'n', 'j')
        vim.api.nvim_buf_del_keymap(buf, 'n', 'k')
        vim.api.nvim_buf_del_keymap(buf, 'n', '<CR>')
        vim.api.nvim_buf_del_keymap(buf, 'n', '<C-c>')
        vim.api.nvim_buf_del_keymap(buf, 'n', '<Esc>')
        vim.api.nvim_buf_del_keymap(buf, 'n', 'q')
        vim.api.nvim_win_close(title_win, true)
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    end

    local function execute()
        vim.api.nvim_win_set_cursor(win, {current_index, 0})
        local cmdname = vim.api.nvim_buf_get_lines(buf, current_index-1, current_index, false)[1]
        local build = corresponding_build_command[cmdname]
        local command_string = build.command()

        close_dialog()

        if vim.fn.isdirectory(build.working_dir) ~= 1 then
            log_msg(build.working_dir .. " is not a valid directory.")
            return
        end
        log_msg("Executing command: " .. command_string .. " (BEFORE CHDIR)")
        vim.fn.chdir(build.working_dir)

        log_msg("Executing command: " .. command_string)
        local result = vim.fn.system(command_string)
        log_msg("Got result: " .. result)

        if vim.v.shell_error ~= 0 then
            log_msg("Command failed with exit code " .. vim.v.shell_error .. ": " .. result)
            return
        end
    end

    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-p>', '', { noremap = true, silent = true, callback = move_up })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-n>', '', { noremap = true, silent = true, callback = move_down })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'k',     '', { noremap = true, silent = true, callback = move_up })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'j',     '', { noremap = true, silent = true, callback = move_down })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>',  '', { noremap = true, silent = false, callback = execute })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c>', '', { noremap = true, silent = true, callback = close_dialog })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', { noremap = true, silent = true, callback = close_dialog })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q',     '', { noremap = true, silent = true, callback = close_dialog })

    vim.api.nvim_win_set_cursor(win, {current_index, 0})
end


local function load_project()
    local files = vim.fn.readdir(ctx.projects_directory)

    local lua_files = {}
    local lua_files_count = 0
    local max_file_name_length = 0

    for _, filename in ipairs(files) do
        if string.match(filename, ".*%.lua$") then
            table.insert(lua_files, filename)
            if max_file_name_length < string.len(filename) then
                max_file_name_length = string.len(filename)
            end
            lua_files_count = lua_files_count + 1
        end
    end
    table.sort(lua_files)
    files = nil

    if lua_files_count == 0 then
        print("There are no projects to load")
        return
    end

    local TITLE = "Projects"
    local terminal_w = vim.o.columns
    local terminal_h = vim.o.lines
    local popup_w = clamp(max_file_name_length, string.len(TITLE), terminal_w)
    local popup_h = math.min(lua_files_count, terminal_h)
    local popup_x = math.floor((terminal_w - popup_w) / 2)
    local popup_y = math.floor((terminal_h - popup_h) / 2)
    
    -- Creating title read only window
    local title_buf = vim.api.nvim_create_buf(false, true)
    local title_win = vim.api.nvim_open_win(title_buf, true, {
        relative = 'editor',
        width = popup_w,
        height = 1,
        col = popup_x,
        row = popup_y - 2,
        style = 'minimal',
        border = 'single',
    })
    vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, {TITLE})
    vim.api.nvim_buf_set_option(title_buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(title_buf, 'buftype', 'nofile')

    -- Creating pop-up
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = popup_w,
        height = popup_h,
        col = popup_x,
        row = popup_y,
        style = 'minimal',
        border = 'single',
    })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lua_files)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')

    local current_index = 1

    local function move_up()
        if current_index > 1 then
            current_index = current_index - 1
        else
            current_index = lua_files_count
        end
        vim.api.nvim_win_set_cursor(win, {current_index, 0})
    end

    local function move_down()
        if current_index < lua_files_count then
            current_index = current_index + 1
        else
            current_index = 1
        end
        vim.api.nvim_win_set_cursor(win, {current_index, 0})
    end

    local function close_dialog()
        vim.api.nvim_buf_del_keymap(buf, 'n', '<C-p>')
        vim.api.nvim_buf_del_keymap(buf, 'n', '<C-n>')
        vim.api.nvim_buf_del_keymap(buf, 'n', 'j')
        vim.api.nvim_buf_del_keymap(buf, 'n', 'k')
        vim.api.nvim_buf_del_keymap(buf, 'n', '<CR>')
        vim.api.nvim_buf_del_keymap(buf, 'n', '<C-c>')
        vim.api.nvim_buf_del_keymap(buf, 'n', '<Esc>')
        vim.api.nvim_buf_del_keymap(buf, 'n', 'q')
        vim.api.nvim_win_close(title_win, true)
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    end

    local function open_file()
        local config_filename = lua_files[current_index]
        ctx.this_project_config = ctx.projects_directory .. config_filename

        vim.fn.execute("edit " .. ctx.this_project_config)
        close_dialog()
        vim.fn.execute("buffer " .. ctx.this_project_config)
        vim.api.nvim_command('luafile %')

        if not is_active() then return end

        local workspace = ctx.this_project_workspace
        recursive_open_files_in_dir(workspace.working_dir, ctx.this_project_file_patterns)
        for _,_ in ipairs(workspace.others) do
            recursive_open_files_in_dir(workspace.working_dir, ctx.this_project_file_patterns)
        end

        vim.fn.execute("buffer " .. ctx.this_project_config)
        print("Open all files in project")
    end

    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-p>', '', { noremap = true, silent = true, callback = move_up })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-n>', '', { noremap = true, silent = true, callback = move_down })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'k',     '', { noremap = true, silent = true, callback = move_up })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'j',     '', { noremap = true, silent = true, callback = move_down })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>',  '', { noremap = true, silent = true, callback = open_file })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c>', '', { noremap = true, silent = true, callback = close_dialog })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', { noremap = true, silent = true, callback = close_dialog })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q',     '', { noremap = true, silent = true, callback = close_dialog })

    vim.api.nvim_win_set_cursor(win, {current_index, 0})
end


local function new_project()
    local terminal_w = vim.o.columns
    local terminal_h = vim.o.lines
    local popup_w = 30
    local popup_h = 1
    local popup_x = math.floor((terminal_w - popup_w) / 2)
    local popup_y = math.floor((terminal_h - popup_h) / 2)

    -- Creating title read only window
    local TITLE = "Project Name"
    local title_buf = vim.api.nvim_create_buf(false, true)
    local title_win = vim.api.nvim_open_win(title_buf, true, {
        relative = 'editor',
        width = popup_w,
        height = 1,
        col = popup_x,
        row = popup_y - 2,
        style = 'minimal',
        border = 'single',
    })
    vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, {TITLE})
    vim.api.nvim_buf_set_option(title_buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(title_buf, 'buftype', 'nofile')

    -- Creating pop-up
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = popup_w,
        height = popup_h,
        col = popup_x,
        row = popup_y,
        style = 'minimal',
        border = 'single',
    })
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_command('startinsert')

    local function cancel()
        vim.api.nvim_buf_del_keymap(buf, 'i', '<Esc>')
        vim.api.nvim_buf_del_keymap(buf, 'i', '<C-c>')
        vim.api.nvim_buf_del_keymap(buf, 'i', '<CR>')
        vim.api.nvim_win_close(title_win, true)
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    end

    local function confirm()
        -- Get the text from the buffer (only first line)
        local user_input = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]

        -- Close the windows.
        vim.api.nvim_buf_del_keymap(buf, 'i', '<Esc>')
        vim.api.nvim_buf_del_keymap(buf, 'i', '<C-c>')
        vim.api.nvim_buf_del_keymap(buf, 'i', '<CR>')
        vim.api.nvim_win_close(title_win, true)
        vim.api.nvim_win_close(win, true)
        
        -- Switch to Normal mode.
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)

        -- Canceling if it is invalid
        if not is_filename_valid(user_input) then return end

        -- Opening the file (Created if it doesn't exist)
        local config_path = ctx.projects_directory .. string.gsub(user_input, ' ', '_') .. '.lua'

        if not file_exists(config_path) then
            local config_file = io.open(config_path, 'a')
            if not config_file then return end
            config_file:write(DEFAULT_CONFIG_STRUCTURE)
            config_file:close()
        end
        
        vim.fn.execute("edit " .. config_path)
        ctx.this_project_config = config_path
    end

    vim.api.nvim_buf_set_keymap(buf, 'i', '<CR>',  '', { noremap = true, silent = true, callback = confirm })
    vim.api.nvim_buf_set_keymap(buf, 'i', '<C-c>', '', { noremap = true, silent = true, callback = cancel })
    vim.api.nvim_buf_set_keymap(buf, 'i', '<Esc>', '', { noremap = true, silent = true, callback = cancel })
end


local function open_project_config()
    if ctx.this_project_config == nil then
        print("No active project.")
        return
    end
    vim.fn.execute("edit " .. ctx.this_project_config)
end


-- Commands
-- ----------------------------------------------------------------------------------------------- --

create_directory_if_needed(ctx.projects_directory)

vim.api.nvim_create_user_command('DumbProjectOpenProjectsDirNetrw', function()
    print(require("dumb-project").open_projects_dir_with_netrw())
end, {})

vim.api.nvim_create_user_command('DumbProjectNew', function()
    print(require("dumb-project").new())
end, {})

vim.api.nvim_create_user_command('DumbProjectLoad', function()
    print(require("dumb-project").load())
end, {})

vim.api.nvim_create_user_command('DumbProjectExec', function()
    print(require("dumb-project").command_lister())
end, {})

vim.api.nvim_create_user_command('DumbProjectOpenConfig', function()
    print(require("dumb-project").open_config())
end, {})


-- Table of the module
-- ----------------------------------------------------------------------------------------------- --

local API_TABLE = {
    get_current_file = get_current_file,
    get_this_project_path = function() return ctx.this_project_file end,
    open_projects_dir_with_netrw = open_projects_dir_with_netrw,
    load = load_project,
    new = new_project,
    command_lister = build_command_lister,
    open_config = open_project_config,
    cmd = make_build_command,
    is_active = is_active,
    setup = setup,
}

return API_TABLE
