local worldpath = core.get_worldpath()
local file_path = worldpath .. "/coordsplus_data.json"


coords = coords or {}
local data = {}
-- Load on start
do
  local f = io.open(file_path, "r")
  if f then
    local content = f:read("*all")
    f:close()
    data = core.parse_json(content) or {}
  end
end

function coords.log(type, msg)
  if type == "info" then
    print("[coordsplus] "..msg)
  elseif type == "action" then
    core.log("action", "[coordsplus]: "..msg)
  elseif type == "warn" then
    core.log("warning", "[coordsplus]: "..msg)
  elseif type == "error" then
    core.log("error", "[coordsplus]: "..msg)
  elseif type == "fatal" then
    error(msg)
  end
end

function coords.save_all()
  local f = io.open(file_path, "w")
  if not f then return false end
  f:write(core.write_json(data))
  f:close()
  return true
end

function coords.erase_db()
  local f = io.open(file_path, "w")
  if not f then return false end
  data = {}
  f:write(core.write_json(nil))
end

local function ensure_player(name)
  if not data[name] then data[name] = {} coords.log("action", "Created entry for '"..name.."' in the coords database.") end
end

function coords.set_coord(name, key, pos)
  ensure_player(name)  -- initialize data[name] if needed
  if data[name][key] then
    return false, "ERROR: That name already exists!"
  end
  data[name][key] = {x = pos.x, y = pos.y, z = pos.z}
  coords.log("action", "Player '"..name.."' created coord with name '"..key.."' at "..pos.x..","..pos.y..","..pos.z..".")
  return coords.save_all()
end


function coords.move_coord(name, key, pos)
  ensure_player(name)
  if data[name][key] then
    data[name][key] = { x = pos.x, y = pos.y, z = pos.z }
    coords.log("action", "Player '"..name.."' moved coord with name '"..key.."' to "..pos.x..","..pos.y..","..pos.z..".")
    return coords.save_all()
  end
  return false, "ERROR: No such coordinate to move"
end

function coords.rename_coord(name, oldkey, newkey)
  ensure_player(name)
  if not data[name][oldkey] then
    return false, "ERROR: Old name doesn't exist!"
  end
  if data[name][newkey] then
    return false, "ERROR: New name already exists!"
  end
  data[name][newkey] = data[name][oldkey]
  data[name][oldkey] = nil
  coords.log("action", "Player '"..name.."' renamed coord with name '"..oldkey.."' to '"..newkey.."'.")
  return coords.save_all()
end

function coords.delete_coord(name, key)
  ensure_player(name)
  if data[name][key] then
    data[name][key] = nil
    coords.log("action", "Player '"..name.."' deleted coord with name '"..key.."'.")
    return coords.save_all()
  end
  return false, "ERROR: No such coordinate to delete"
end

function coords.list_coords(name)
  if not data[name] or next(data[name]) == nil then
    return false, nil, "ERROR: No coords matching the target player!"
  end
  local lines = {}
  for k,v in pairs(data[name]) do
    table.insert(lines, string.format("%s: (%.1f, %.1f, %.1f)",
      k, v.x, v.y, v.z))
  end
  table.sort(lines)
  return true, lines
end

local function tp_coord(name, key)
  if not data[name] then return false, "ERROR: DB for player name is empty!" end
  if not data[name][key] then return false, "ERROR: The requested entry could not be found" end
  local entry = data[name][key]
  local tppos = {x=tonumber(entry.x),y=tonumber(entry.y),z=tonumber(entry.z)}
  core.get_player_by_name(name):set_pos(tppos)
  return true
end


core.register_privilege("coords_admin", {
    description = "Can manage the entire coords database",
    give_to_singleplayer = false
})


core.register_chatcommand("coords", {
  params = "<action> [...]", description = "Manage saved coordinates",
  func = function(name, param)
    local p = core.get_player_by_name(name)
    if not p then return false, "ERROR: Player not found" end

    local args = {}
    for w in param:gmatch("%S+") do table.insert(args, w) end
    local action = args[1]


    --Create
    if action == "create" and args[2] then
      local key = args[2]
      local pos = args[3] and args[3]:match("^%(([^)]+)%)$")
      if pos then
        local x,y,z = pos:match("([-0-9%.]+),([-0-9%.]+),([-0-9%.]+)")
        pos = { x=string.format("%.1f", x), y=string.format("%.1f", y), z=string.format("%.1f", z)}
      elseif args[3] == "here" then
        temppos = p:get_pos()
        pos = { x=string.format("%.1f", temppos["x"]), y=string.format("%.1f", temppos["y"]), z=string.format("%.1f", temppos["z"])}
      else
        return false, "ERROR: Postion *must* be either 'here' or (x,y,z)."
      end
      local ok, msg = coords.set_coord(name, key, pos)
      return ok, ok and ("Created "..key.." at "..pos.x..","..pos.y..","..pos.z.."!") or msg


    --Move
    elseif action == "move" and args[2] then
      local key = args[2]
      local pos = args[3] and args[3]:match("^%(([^)]+)%)$")
      if pos then
        local x,y,z = pos:match("([-0-9%.]+),([-0-9%.]+),([-0-9%.]+)")
        pos = { x=tonumber(x), y=tonumber(y), z=tonumber(z) }
      else
        pos = p:get_pos()
      end
      local ok = coords.move_coord(name, key, pos)
      return ok, ok and ("Moved '"..key.."'") or "Move failed or not exist"


    --Rename
    elseif action == "rename" and args[2] and args[3] then
      local ok = coords.rename_coord(name, args[2], args[3])
      return ok, ok and ("Renamed '"..args[2].."'→'"..args[3].."'") or "Rename failed"


    --Delete
    elseif action == "delete" and args[2] then
      local ok, msg = coords.delete_coord(name, args[2])
      return ok, ok and "Sucessfully deleted "..args[2].."!" or msg


    --List
    elseif action == "list" then
      if args[2] then 
        local ok, lines, msg = coords.list_coords(args[2])
        if core.check_player_privs(name, {coords_admin = true}) == false then return false, "ERROR: You are not a coords admin!" end
        if not lines then return false, "ERROR: User has no coords saved" end
        return ok, ok and "Saved coords:\n" .. table.concat(lines, "\n") or msg
      elseif not args[2] then
        local ok, lines, msg = coords.list_coords(name)
        if not lines then return false, "ERROR: You have no saved coords" end
        return ok, ok and "Saved coords:\n" .. table.concat(lines, "\n") or msg
      end


    --Teleport
    elseif action == "teleport" or action == "tp" then
      if core.check_player_privs(name, { teleport = true }) == false then return false, "ERROR: You cannot tp without the teleport privilege!" end
      local ok, msg = tp_coord(name, args[2])
      return ok, ok and "Teleport success!" or msg
    else
      return false,
        "Usage: /coords create <name> [(x,y,z)]\n"..
        "       move <name> [(x,y,z)]\n"..
        "       rename <old> <new>\n"..
        "       delete <name>\n"..
        "       list\n"..
        "       teleport <name>"
    end
  end,
})
coords.log("info", "mod loaded!")