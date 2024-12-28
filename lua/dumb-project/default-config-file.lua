
return [[
local project = require('dumb-project')

-- List of accepted file patterns.

local file_patterns = {
    "*.c",
    "*.odin",
    "*.glsl",
    "*.bat",
    "*.sh",
}

-- List of folders to recursively scan.
-- Unfortunately things like ~ don't work.

local workspace = {
    working_dir = "~/dev/project",
    others = {
        "/home/user/libs/library1",
        "/home/user/libs/library2",
        "/home/user/libs/library3",
    },
}

-- List of build commands to use.
-- Each command must be a table{cmdname: string, command: function(returns_string), binding: string}.
-- The require('dumb-project').cmd function assists with creating commands by allowing strings and functions that return strings. 
-- The default working_dir for all commands is the workspace.working_dir.

local build_commands = {
    {
        cmdname = "Build",
        command = project.cmd("build.bat"),
        binding = "<F5>",
    },
    {
        cmdname = "RunFile",
        command = project.cmd("odin run", project.get_current_file, " -file"),
        binding = "<F6>",
    },
    {
        cmdname = "CompileLibrary1",
        command = project.cmd("make && sudo make install"),
        binding = "<F6>",
        working_dir = "/home/user/libs/library1",
    },
}

-- Must call this function to use all the tables defined previously.
project.setup_config(file_patterns, workspace, build_commands)

]]
