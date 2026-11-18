local JSON = require("rapidjson")
local SQLite = require("lua-ljsqlite3/init")

local Expansion = {}
Expansion.__index = Expansion

function Expansion.open(path)
    local ok, db = pcall(SQLite.open, path, "ro")
    if not ok then return nil end

    local loaded, entries = pcall(function()
        assert(db:rowexec("PRAGMA user_version") == 1)
        local rows = db:prepare("SELECT id, rating, themes, stage_count FROM puzzles ORDER BY position")
        local result = {}
        for row in rows:rows() do
            result[#result + 1] = { id = row[1], rating = row[2], themes = row[3], stage_count = row[4] }
        end
        rows:close()
        assert(#result > 0)
        return result
    end)
    if not loaded then
        db:close()
        return nil
    end
    return setmetatable({ db = db, entries = entries }, Expansion)
end

function Expansion:loadSteps(id)
    local statement = self.db:prepare("SELECT steps FROM puzzles WHERE id = ?")
    local row = statement:bind(id):step()
    statement:close()
    return JSON.decode(row[1])
end

function Expansion:close()
    self.db:close()
end

return Expansion
