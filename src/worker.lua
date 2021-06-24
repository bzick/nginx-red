local red = red
local log = require("log")
if red then
    local ok, err = pcall(red.start_file_watcher)
    if ok then
        log.debug("File watcher started")
    else
        log.err("Filed to start file watcher: " .. err)
    end
else
    log.err("File watcher not started. Project RED not initialized?")
end
