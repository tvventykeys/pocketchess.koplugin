-- Versioned text data, parsed without evaluating Lua from disk.
local Progress = {}
local HEADER = "pocketchess-progress-v1"

local function empty(puzzles)
    return { current = puzzles[1].id, entries = {} }
end

function Progress.load(path, puzzles)
    local file = io.open(path, "rb")
    if not file then return empty(puzzles) end

    local limit = 128 + #puzzles * 32
    local data = file:read(limit + 1) or ""
    file:close()
    if #data > limit or data:sub(-1) ~= "\n" then return empty(puzzles), true end

    local allowed = {}
    for _, puzzle in ipairs(puzzles) do
        allowed[puzzle.id] = puzzle.stage_count or #puzzle.steps
    end
    local header, current, rows = data:match("^([^\n]+)\n([^\n]+)\n(.*)$")
    if header ~= HEADER or not current:match("^[A-Za-z0-9]+$") then
        return empty(puzzles), true
    end

    local state, seen = empty(puzzles), {}
    if allowed[current] then state.current = current end
    for row in rows:gmatch("([^\n]*)\n") do
        local id, stage, solved, revealed = row:match("^([A-Za-z0-9]+) (%d+) ([01]) ([01])$")
        if not id or seen[id] then return empty(puzzles), true end
        seen[id] = true
        if allowed[id] then
            stage = tonumber(stage)
            local final = stage == allowed[id]
            if stage < 1 or stage > allowed[id]
                or (revealed == "1" and not final)
                or (final and solved == "0" and revealed == "0") then
                return empty(puzzles), true
            end
            state.entries[id] = { stage = stage, solved = solved == "1", revealed = revealed == "1" }
        end
    end
    return state
end

function Progress.save(path, state)
    local ids = {}
    for id in pairs(state.entries) do ids[#ids + 1] = id end
    table.sort(ids)
    local rows = { HEADER, state.current }
    for _, id in ipairs(ids) do
        local entry = state.entries[id]
        rows[#rows + 1] = string.format("%s %d %d %d", id, entry.stage,
            entry.solved and 1 or 0, entry.revealed and 1 or 0)
    end

    local temp = path .. ".tmp"
    local file, err = io.open(temp, "wb")
    if not file then return nil, err end
    local written, write_err = file:write(table.concat(rows, "\n") .. "\n")
    local closed, close_err = file:close()
    if not written or not closed then
        os.remove(temp)
        return nil, write_err or close_err
    end
    local replaced, rename_err = os.rename(temp, path)
    if not replaced then os.remove(temp) end
    return replaced, rename_err
end

return Progress
