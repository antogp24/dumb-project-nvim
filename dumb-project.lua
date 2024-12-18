
-- Global state of the plugin.
-- ----------------------------------------------------------------------------------------------- --

local ctx = {
    this_path = nil,
    this_config = nil,
    this_file_patterns = nil,
    this_workspace = nil,
    this_build_commands = nil,
    created_bindings = {}
}

local PROJECTS_DIRECTORY = vim.fs.normalize(vim.fn.stdpath('config')) .. '/dumb-project/'

-- Default contents of the config file.
-- ----------------------------------------------------------------------------------------------- --

local function make_default_config_file_header()
    local current_date = os.date("%d-%m-%Y %H:%M:%S")
    return string.format("-- Project config file created at %s\n", current_date)
end

local DEFAULT_CONFIG_FILE_BODY = require("default-config-file")

-- Helper functions
-- ----------------------------------------------------------------------------------------------- --

local function log_msg(message, no_newline)
    local file = io.open('W:/dumb-project-nvim/log.txt', 'a')
    if not file then
        error("Error: Could not open log file for writing.")
        return
    end
    if no_newline then 
        file:write(tostring(message))
    else
        file:write(tostring(message) .. "\n")
    end
    file:close()
end


local function file_exists(path)
    return vim.loop.fs_stat(path) and vim.loop.fs_stat(path).type == 'file'
end


local function netrw_open_dir(dir_path)
    if vim.fn.isdirectory(dir_path) ~= 1 then
        error('Could not open the directory: ' .. dir_path)
        return
    end
    vim.cmd('Explore ' .. dir_path)
end


local function close_saved_buffers()
    local buffers = vim.api.nvim_list_bufs()
    for _, buf in ipairs(buffers) do
        vim.api.nvim_buf_delete(buf, { force = false })
    end
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


local function table_sliced(t, start, finish)
    local size = table_size(t)
    if finish == nil then finish = size end

    if start < 1 or finish > size then return end

    local result = {}

    for i = start, finish do
        table.insert(result, t[i])
    end

    return result
end


local function list_print(t, print_fn)
    if not print_fn then print_fn = print end
    local result = "{"
    for i,v in ipairs(t) do
        if i > 1 then result = result .. ", " end
        result = result .. tostring(v)
    end
    result = result .. "}"
    print_fn(result)
end


local function table_print(t, print_fn, indent)
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


local function async_command_run(command_list)
    local command_args = table_sliced(command_list, 2, nil)

    local handle, pid = vim.uv.spawn(command_list[1], {
        args = command_args,
        stdio = {stdin, stdout, stderr},
        verbatim = true,
        detached = true,
        cwd = vim.fn.getcwd(),
    })

    print("handle: " .. tostring(handle) .. ", pid: " .. tostring(pid))
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
    return ctx.this_file_patterns ~= nil and ctx.this_workspace ~= nil and ctx.this_build_commands ~= nil
end


local function clear_this_attribs()
    ctx.this_workspace = nil
    ctx.this_file_patterns = nil
    ctx.this_build_commands = nil
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


local function does_keybinding_exist(key)
    local keymaps = vim.api.nvim_get_keymap('n')
    for _, keymap in ipairs(keymaps) do
        if keymap.lhs == key then
            return true
        end
    end
    return false
end


local function create_key_bindings(build_commands)
    for _, build_command in ipairs(build_commands) do
        local binding = build_command.binding
        local command = function()
            async_command_run(build_command.command())
        end

        vim.keymap.set('n', binding, command, { silent = true })

        if not does_keybinding_exist(binding) then
            print("Error binding", binding .. ":", tostring(command))
        else
            table.insert(ctx.created_bindings, binding)
        end
    end
end


local function clear_key_bindings()
    for _, key in ipairs(ctx.created_bindings) do
        pcall(function()
            vim.api.nvim_del_keymap('n', key)
        end)
    end
    ctx.created_bindings = {}
end


-- Commands
-- ----------------------------------------------------------------------------------------------- --

vim.api.nvim_create_user_command('DumbProjectOpenProjectsDirNetrw', function()
    print(require("dumb-project").netrw_open_projects_dir())
end, {})

vim.api.nvim_create_user_command('DumbProjectNew', function()
    print(require("dumb-project").create_new_project())
end, {})

vim.api.nvim_create_user_command('DumbProjectLoad', function()
    print(require("dumb-project").load())
end, {})

vim.api.nvim_create_user_command('DumbProjectUnload', function()
    print(require("dumb-project").unload())
end, {})

vim.api.nvim_create_user_command('DumbProjectExec', function()
    print(require("dumb-project").command_lister())
end, {})

vim.api.nvim_create_user_command('DumbProjectOpenConfig', function()
    print(require("dumb-project").open_config())
end, {})


create_directory_if_needed(PROJECTS_DIRECTORY)

-- API
-- ----------------------------------------------------------------------------------------------- --

local API = {}


function API.setup(file_patterns, workspace, build_commands)
    clear_this_attribs()

    if validate_file_patterns(file_patterns) then
        ctx.this_file_patterns = file_patterns
    end
    if validate_workspace(workspace) then
        ctx.this_workspace = workspace
    end
    if validate_build_commands(build_commands, ctx.this_workspace) then
        ctx.this_build_commands = build_commands
    end

    if not is_active() then
        clear_this_attribs()
        return false
    end

    return true
end


function API.cmd(...)
    local num_args = select("#", ...)
    if num_args == 0 then
        error("Expected the function make_build_command to have arguments, but recieved none.")
    end
    local command_args = {}

    for i = 1, num_args do
        local v = select(i, ...)
        local arg_type = type(v)

        if arg_type ~= "string" and arg_type ~= "function" then
            error("Expected strings or functions in require('dumb-project').cmd(...), but got " .. arg_type)
            return nil
        elseif arg_type == "function" then
            local return_type = type(v())
            if return_type ~= "string" then
                error("Functions in require('dumb-project').cmd(...) must return a string, but got " .. return_type)
                return nil
            end
        end

        table.insert(command_args, v)
    end

    return function()
        local result = {}
        for _,v in ipairs(command_args) do
            if type(v) == "function" then
                table.insert(result, v())
            else
                table.insert(result, v)
            end
        end
        return result
    end
end


function API.command_lister()
    if ctx.this_build_commands == nil or table_size(ctx.this_build_commands) == 0 then
        print("No available build commands.")
        return
    end

    local command_names = {}
    local corresponding_build_command = {}
    local max_cmdname_length = 0
    local build_commands_count = 0

    for _,v in ipairs(ctx.this_build_commands) do
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
        close_dialog()

        local command_list = build.command()
        async_command_run(command_list)
    end

    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-p>', '', { noremap = true, silent = true,  callback = move_up      })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-n>', '', { noremap = true, silent = true,  callback = move_down    })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'k',     '', { noremap = true, silent = true,  callback = move_up      })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'j',     '', { noremap = true, silent = true,  callback = move_down    })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>',  '', { noremap = true, silent = false, callback = execute      })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c>', '', { noremap = true, silent = true,  callback = close_dialog })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', { noremap = true, silent = true,  callback = close_dialog })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q',     '', { noremap = true, silent = true,  callback = close_dialog })

    vim.api.nvim_win_set_cursor(win, {current_index, 0})
end


function API.load()
    local files = vim.fn.readdir(PROJECTS_DIRECTORY)

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

    local function open_config()
        local config_filename = lua_files[current_index]
        ctx.this_config = PROJECTS_DIRECTORY .. config_filename

        vim.fn.execute("edit " .. ctx.this_config)
        close_dialog()
        vim.fn.execute("buffer " .. ctx.this_config)
        vim.api.nvim_command('luafile %')

        if not is_active() then 
            error("At the end in " .. ctx.this_config .. " you must call the setup function.")
            return
        end

        local workspace = ctx.this_workspace

        if vim.fn.isdirectory(workspace.working_dir) ~= 1 then
            error(build.working_dir .. " is not a valid directory.")
            return
        end

        recursive_open_files_in_dir(workspace.working_dir, ctx.this_file_patterns)
        for _,_ in ipairs(workspace.others) do
            recursive_open_files_in_dir(workspace.working_dir, ctx.this_file_patterns, true)
        end

        vim.fn.chdir(workspace.working_dir)
        vim.fn.execute("buffer " .. ctx.this_config)
        print("Opened all files in project")

        create_key_bindings(ctx.this_build_commands)
    end

    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-p>', '', { noremap = true, silent = true, callback = move_up      })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-n>', '', { noremap = true, silent = true, callback = move_down    })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'k',     '', { noremap = true, silent = true, callback = move_up      })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'j',     '', { noremap = true, silent = true, callback = move_down    })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>',  '', { noremap = true, silent = true, callback = open_config  })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c>', '', { noremap = true, silent = true, callback = close_dialog })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', { noremap = true, silent = true, callback = close_dialog })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q',     '', { noremap = true, silent = true, callback = close_dialog })

    vim.api.nvim_win_set_cursor(win, {current_index, 0})
end


function API.create_new_project()
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
        local config_path = PROJECTS_DIRECTORY .. string.gsub(user_input, ' ', '_') .. '.lua'

        if not file_exists(config_path) then
            local config_file = io.open(config_path, 'a')
            if not config_file then return end
            config_file:write(make_default_config_file_header())
            config_file:write(DEFAULT_CONFIG_FILE_BODY)
            config_file:close()
        end
        
        vim.fn.execute("edit " .. config_path)
        ctx.this_config = config_path
    end

    vim.api.nvim_buf_set_keymap(buf, 'i', '<CR>',  '', { noremap = true, silent = true, callback = confirm })
    vim.api.nvim_buf_set_keymap(buf, 'i', '<C-c>', '', { noremap = true, silent = true, callback = cancel  })
    vim.api.nvim_buf_set_keymap(buf, 'i', '<Esc>', '', { noremap = true, silent = true, callback = cancel  })
end


function API.open_config()
    if ctx.this_config == nil then
        print("No active project.")
        return
    end
    vim.fn.execute("edit " .. ctx.this_config)
end


function API.unload()
    ctx.this_path = nil
    ctx.this_config = nil
    ctx.this_file_patterns = nil
    ctx.this_workspace = nil
    ctx.this_build_commands = nil
    clear_key_bindings()
    close_saved_buffers()
    vim.fn.chdir(PROJECTS_DIRECTORY)
    netrw_open_dir(PROJECTS_DIRECTORY)
end


function API.netrw_open_projects_dir()
    netrw_open_dir(PROJECTS_DIRECTORY)
end


function API.get_current_file()
    return vim.fn.expand('%:p')
end


function API.get_project_path()
    return ctx.this_file
end


return API
