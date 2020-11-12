local HEAD = 0
local LAYER_OFFSET = 0x4
local OP_LENGTH  = 0x4
local OCTAL_OFFSET = 0x21
local LENGTH_OFFSET = 0x4
local FILENAME_OFFSET = 0x35
local FILENAME_LENGTH_OFFSET = 0x31

local function read(handle)
    HEAD = HEAD + 1
    return handle.read()
end

local function ReadByte(handle)
    local byte = read(handle)
    local hex= string.format("%x", byte)
    return tonumber(hex)
end

local function ReadBytesToDec(handle, bytesToRead)
    local number = 0
    for i=1, bytesToRead do
        local byte = read(handle)
        if i == 1 then byte = byte else byte = (byte * math.pow(256, (i-1)) ) end
        number = number + byte
    end
    return number
end

local function SkipBytes(handle, offset)
    for i=1, tonumber(offset) do
        read(handle)
    end
end

local function DecToHex(number)
    local hex_string = string.format("%x", number)
    return tonumber(hex_string)
end

local function GetHeaderInfo(handle)
    local header_info = {}

    --song tick length
    SkipBytes(handle, LENGTH_OFFSET)
    header_info.tick_length = ReadBytesToDec(handle, 2)
    
    
    --song title length
    local song_title_length = 0
    SkipBytes(handle, FILENAME_LENGTH_OFFSET - HEAD)
    song_title_length = ReadBytesToDec(handle, 2)
    
    --song title
    local song_title = ""
    SkipBytes(handle, FILENAME_OFFSET - HEAD)
    for i=1, song_title_length do
        local char = read(handle)
        song_title = song_title .. string.char(char)
    end
    header_info.song_title = song_title

    SkipBytes(handle, OP_LENGTH)
    return header_info

end

local function GetNote(handle)
    local note = {}
    for i=1, OP_LENGTH do
        local byte = read(handle)
        table.insert(note, byte)
    end
    return note
end

local function GetJumpOp(handle)
    local OpCode = {}
    
    local tick = ReadBytesToDec(handle, 2)
    OpCode.tick_jump = tick

    local layer = ReadBytesToDec(handle, 2)
    OpCode.layer_jump = layer

    if tick == 0 and layer == 0 then
        return nil
    end
    return OpCode
end

--THE HEAD NEEDS TO BE PLACED AT THE BACK OF A NOTE
--Not ensuring that will result in a undefined behavior
--#TODO return the correct layer jump
--return the JumpOp to the next note while moving the head to it
--local function FindNextNote(handle)
--    local sum = 0
--    for i=1, LAYER_OFFSET do
--        local byte = read(handle)
--        sum = sum + byte
--        if i == LAYER_OFFSET and sum >= 1 then
--            return {0, byte}
--       end
--    end
--    return GetJumpOp(handle)
--end

local function GetLayerJump(handle)
    local Op = {tick_jump = 0, layer_jump = 0}
    SkipBytes(handle, LAYER_OFFSET / 2)
    Op.layer_jump = ReadBytesToDec(handle, 2)

    if Op.layer_jump == 0 then return nil end
    return Op
end

local function GetNextTick(handle)
    local notes = {}
    while true do
        table.insert(notes, GetNote(handle))
        local Op = GetLayerJump(handle)
        if Op == nil then
            return notes
        end
    end
end

local function parse_song(handle, header_info, starting_tick)
    local parsed_song = {}
    local tick = starting_tick
    while true do
        local section = GetNextTick(handle)
        table.insert(parsed_song, {tick, section})
        
        if tick == header_info.tick_length then
            return parsed_song
        end
    
        local Op = GetJumpOp(handle)
        tick = tick + Op.tick_jump
    end
end

local sTick = 0

local formatted_song = {}

local song = fs.open("crawl.nbs", "rb")
local header_info = GetHeaderInfo(song)
print(header_info.tick_length)
print(header_info.song_title)

local Op = GetJumpOp(song)
local pSong = parse_song(song, header_info, Op.tick_jump -1)

for i=1, #pSong do
    print("tick: " .. pSong[i][1] .. " found " .. #pSong[i][2] .. " notes.")
end