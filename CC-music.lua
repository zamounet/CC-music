local currentPath = "CC-music/"

do
	local requireCache = {}
	
	function require(file, global)
		global = global or false
		local absolute = file
		
		if global == false then
			absolute = currentPath .. file
        end
        if requireCache[absolute] ~= nil then
          --# Lucky day, this file has already been loaded once!
          --# Return its cached result.
          return requireCache[absolute]
        end

        --# Create a custom environment so that loaded
        --# source files also have access to require.
        local env = {
          require = require
        }

        setmetatable(env, { __index = _G, __newindex = _G })

        --# Load the source file with loadfile, which
        --# also allows us to pass our custom environment.
        local chunk, err = loadfile(absolute, env)

        --# If chunk is nil, then there was a syntax error
        --# or the file does not exist.
        if chunk == nil then
          return error(err)
        end

        --# Execute the file, cache and return its return value.
        local result = chunk()
        requireCache[absolute] = result
        return result
  end
end
local json = require("json")

local function ReadBytesToDec(handle, bytesToRead)
    local number = 0
    for i=1, bytesToRead do
        local byte = handle.read()
        if i == 1 then byte = byte else byte = (byte * math.pow(256, (i-1)) ) end
        number = number + byte
    end
    return number
end

local function ReadByte(handle)
    return ReadBytesToDec(handle, 1)
end

local function ReadShort(handle)
    return ReadBytesToDec(handle, 2)
end

local function ReadInt(handle)
    return ReadBytesToDec(handle, 4)
end

local function ReadString(handle)
    local string_length = ReadInt(handle)
    local string = ""

    for i=1, string_length do
        local byte = handle.read()
        string = string .. string.char(byte)
    end
    return string
end

local function GetHeaderInfo(handle)
    local header_info = {}
    
    if ReadShort(handle) ~= 0 then
        handle.close()
        error("File version is invalid")
    end
    header_info.version                     = ReadByte(handle)
    header_info.vanilla_instrument_count    = ReadByte(handle)
    header_info.song_length                 = ReadShort(handle)
    header_info.layer_count                 = ReadShort(handle)
    header_info.song_name                   = ReadString(handle)
    header_info.song_author                 = ReadString(handle)
    header_info.song_original_author        = ReadString(handle)
    header_info.song_description            = ReadString(handle)
    header_info.song_tempo                  = ReadShort(handle)
    header_info.auto_saving                 = ReadByte(handle)
    header_info.auto_saving_duration        = ReadByte(handle)
    header_info.time_signature              = ReadByte(handle)
    header_info.minute_spent                = ReadInt(handle)
    header_info.left_clicks                 = ReadInt(handle)
    header_info.right_clicks                = ReadInt(handle)
    header_info.note_blocks_added           = ReadInt(handle)
    header_info.note_blocks_removed         = ReadInt(handle)
    header_info.schematic_file_name         = ReadString(handle)
    header_info.loop_state                  = ReadByte(handle)
    header_info.max_loop_count              = ReadByte(handle)
    header_info.loop_start_tick             = ReadShort(handle)
    return header_info

end

local function GetNotes(handle)
    local notes = {}
    local current_tick = -1
    while true do
        local tick_jump = ReadShort(handle)
        if tick_jump == 0 then break end
        current_tick = current_tick + tick_jump
        
        notes[current_tick] = {}
        local layer = -1
        while true do
            local layer_jump = ReadShort(handle)
            if layer_jump == 0 then break end
            layer = layer + layer_jump

            local note = {}
            note.instrument  = ReadByte(handle)
            note.key         = ReadByte(handle)
            note.velocity    = ReadByte(handle)
            note.panning     = ReadByte(handle)
            note.pitch       = ReadShort(handle)

            notes[current_tick][layer] = note
        end
        
    end
    return notes
end

local function GetLayers(handle, header)
    local layers = {}
    for i=0, header.layer_count -1 do
        local layer = {}
        
        layer.layer_name    = ReadString(handle)
        layer.layer_lock    = ReadByte(handle)
        layer.layer_volume = ReadByte(handle)
        layer.layer_stereo  = ReadByte(handle)

        layers[i] = layer
    end
    return layers
end

local function PlayNote(note, layer, instruments, noteblock)
    --will have to do something about stereo
    
    -- 0 is 2 blocks right, 100 is center, 200 is 2 blocks left.
    
    -- Pitch source https://minecraft.gamepedia.com/Note_Block
    noteblock.playSound(instruments[tostring(note.instrument)], math.pow(2, ((note.key - 33) - 12) / 12), layer.layer_volume, 0, 0, 0)
end

local function PlayTick(tick, layers, instruments, noteblock)
    for layer, note in pairs(tick) do
        PlayNote(note, layers[layer], instruments, noteblock)
    end
end


local function PlaySong(song, noteblock)
    local clock = os.clock()
    local tempo = song.header.song_tempo / 100 -- ticks per second
    local delta_time = 0
    local current_tick = 0
    while true do
        local new_clock = os.clock()
        delta_time = delta_time + (new_clock - clock)

        while delta_time >= (1 / tempo) do
            delta_time = delta_time - (1 / tempo)
            
            if song.notes[current_tick] then
                PlayTick(song.notes[current_tick], song.layers, song.instruments, noteblock)
            end

            current_tick = current_tick + 1
        end
        if current_tick > song.header.song_length then
            break
        end
        sleep(0)
        clock = new_clock
    end
end

local noteblock = peripheral.find("note_block")
if not noteblock then
    error("No noteblock detected")
end

local arg = {...}
local song = {}

local song_handle = fs.open(arg[1], "rb")
local instruments_handle = fs.open(currentPath .. "instrument_const.json", "r")

song.header = GetHeaderInfo(song_handle)
song.notes = GetNotes(song_handle)
song.layers = GetLayers(song_handle, song.header)
song_handle.close()

song.instruments = json.decode(instruments_handle.readAll())
instruments_handle.close()

PlaySong(song, noteblock)