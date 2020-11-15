local instruments = {"minecraft:note.harp", "minecraft:note.bassattack", "minecraft:note.bass",
                    "minecraft:note.snare", "minecraft:note.hat", "minecraft:note.pling",
                    "flute", "bell", "chime", "xylophone", "iron_xylophone", "cow_bell",
                    "didgeridoo", "bit", "banjo", "minecraft:note.pling"}

local function RaiseError(error_string)
    if shell then
        error(error_string)
    else
        return nil
    end
end
                    
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
    
    local valid = ReadShort(handle)

    if valid ~= 0 or valid == nil then
        handle.close()
        return RaiseError("File version is invalid")
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
        layer.layer_volume  = ReadByte(handle)
        layer.layer_stereo  = ReadByte(handle)

        layers[i] = layer
    end
    return layers
end

local function PlayNote(note, layer, instruments, noteblock)
    --will have to do something about stereo
    
    -- 0 is 2 blocks right, 100 is center, 200 is 2 blocks left.
    
    -- Pitch source https://minecraft.gamepedia.com/Note_Block
    noteblock.playSound(instruments[note.instrument+1], math.pow(2, ((note.key - 33) - 12) / 12), layer.layer_volume, 0, 0, 0)
end

local function PlayTick(tick, layers, instruments, noteblock)
    for layer, note in pairs(tick) do
        PlayNote(note, layers[layer], instruments, noteblock)
    end
end


function PlaySong(song, noteblock)
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

local function GetSongPath(path)
    local error_msg = nil

    if fs.exists(path) == false then
        error_msg = fs.getName(path) .. " does not exist"
    elseif fs.isDir(path) then
        error_msg = "Cannot load a folder"
    end

    if fs.exists("songs/" .. fs.getName(path)) and fs.isDir("songs/" .. fs.getName(path)) == false and error_msg ~= nil then
        path = "songs/" .. fs.getName(path)
        error_msg = nil
    end

    if error_msg then
        return RaiseError(error_msg)
    else
        return path
    end
end

function LoadSong(path)
    local song = {}
    
    path = GetSongPath(path)
    if path == nil then
        return nil
    end

    local song_handle = fs.open(path, "rb")

    song.header = GetHeaderInfo(song_handle)
    if song.header == nil then return nil end -- Invalid file

    song.notes = GetNotes(song_handle)
    song.layers = GetLayers(song_handle, song.header)
    song.instruments = instruments
    song_handle.close()
    return song
end

function FindNoteblock()
    local noteblock = peripheral.find("note_block")
    if not noteblock then
        if shell then
            error("No noteblock detected")
        else
            return nil
        end
    end
    return noteblock
end

if shell then
    local arg = {...}

    if #arg == 0 then
        print("usage: CCMusic <path>")
        return false
    end

    local noteblock = FindNoteblock()
    local song = LoadSong(shell.resolve(arg[1]))

    PlaySong(song, noteblock)
end