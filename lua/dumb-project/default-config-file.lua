
return [[
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
