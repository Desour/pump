--[[

______  __ __  _____ ______
\____ \|  |  \/     \\____ \
|  |_> >  |  /  Y Y  \  |_> >
|   __/|____/|__|_|  /   __/
|__|               \/|__|
--]]

local load_time_start = os.clock()
local modname = minetest.get_current_modname()


-- Something to save meta information instead of getting is all time:
local get_data, set_data, hard_data
do
	local data = {}
	function get_data(pos)
		local hashed_pos = minetest.hash_node_position(pos)
		if not data[hashed_pos] then
			local meta = minetest.get_meta(pos)
			data[hashed_pos] = meta:to_table().fields
		end
		return data[hashed_pos]
	end
	function set_data(pos, t, hard)
		local hashed_pos = minetest.hash_node_position(pos)
		data[hashed_pos] = t
		if not hard then
			return
		end
		local meta = minetest.get_meta(pos)
		meta:from_table({fields = t})
	end
	function hard_data(pos)
		local hashed_pos = minetest.hash_node_position(pos)
		local meta = minetest.get_meta(pos)
		meta:from_table({fields = data[hashed_pos]})
	end
end
--~ minetest.register_on_dignode(function(pos, oldnode, digger)
	--~ set_data(pos, nil, true)
--~ end)

local liquids = {}
minetest.after(0, function()
	for node_name, node_def in pairs(minetest.registered_nodes) do
		if node_def.liquidtype == "source" and
				minetest.get_item_group(node_name, "not_pumpable") ~= 1 then
			liquids[node_name] = {
				source = node_def.liquid_alternative_source,
				flowing = node_def.liquid_alternative_flowing,
				viscosity = node_def.liquid_viscosity,
				renewable = node_def.liquid_renewable,
			}
		end
	end
end)

local function is_liquid(pos)
	local node_name = minetest.get_node(pos).name
	for liquid, def in pairs(liquids) do
		if node_name == def.source then
			return "source", liquid
		elseif node_name == def.flowing then
			return "flowing", liquid
		end
	end
	return false
end

local function get_connected(startpos, nodes, connected, VoxelManip, minp, maxp, hashed_pos, dir)
	local node = VoxelManip:get_node_at(startpos)
	connected[hashed_pos] = nodes[node.name] or false
	if not nodes[node.name] then
		return connected
	end
	local xyz = {"x", "y", "z"}
	for p = 1, 3 do
		for i = dir[2] * -1, dir[2], 2 * dir[2] do
			local pos = vector.new(startpos)
			pos[xyz[p]] = pos[xyz[p]] + i
			hashed_pos = minetest.hash_node_position(pos)
			if connected[hashed_pos] == nil and pos[xyz[p]] > minp[xyz[p]] and
					pos[xyz[p]] < maxp[xyz[p]] then
				connected = get_connected(pos, nodes, connected,
						VoxelManip, minp, maxp, hashed_pos, dir)
			end
			if xyz[p] == dir[1] then
				break
			end
		end
	end
	return connected
end

-- Returns the pos of the liquid source that should be pumped next.
local function get_liquid_pos(pos, liquid, dir)
	-- Get all (to side or to pumpdirection) connected.
	local VoxelManip = minetest.get_voxel_manip()
	local minp, maxp = VoxelManip:read_from_map(vector.add(pos, -50), vector.add(pos, 50))
	local connected_o = get_connected(pos, {
		[liquids[liquid].source] = "s",
		[liquids[liquid].flowing] = "f",
	}, {}, VoxelManip, minp, maxp, minetest.hash_node_position(pos), dir)
	local connected = {}
	for h, t in pairs(connected_o) do
		if t == "s" then
			connected[#connected+1] = minetest.get_position_from_hash(h)
		end
	end
	-- Choose the nearest ones in altitude.
	local outposss = {}
	for i = 1, #connected do
		if not outposss[1] or (dir[2] < 0 and outposss[1][dir[1]] < connected[i][dir[1]])
				or (dir[2] > 0 and outposss[1][dir[1]] > connected[i][dir[1]]) then
			outposss = {connected[i]}
		elseif outposss[1][dir[1]] == connected[i][dir[1]] then
			outposss[#outposss+1] = connected[i]
		end
	end
	-- Choose the ones that are most far away.
	local outposs = {}
	local maxdist = 0
	for i = 1, #outposss do
		local dist = vector.distance(pos, outposss[i])
		if dist >= maxdist then
			maxdist = dist
			outposs[#outposs+1] = outposss[i]
		end
	end
	-- If it are more than one, choose by random.
	local outpos = outposs[math.random(#outposs)]
	return outpos
end

local function step(pos)
	local data = get_data(pos)
	local xyz = {"x", "y", "z"}
	data.dir = data.dir or -2
	local dir = math.abs(data.dir)
	dir = {xyz[dir], data.dir/dir}
	if data.mode == "extend" then
		local old_pos = vector.new(pos)
		data.pipe_length = data.pipe_length or 0
		pos[dir[1]] = pos[dir[1]] + (data.pipe_length * dir[2])
		local node
		repeat
			data.pipe_length = data.pipe_length + 1
			pos[dir[1]] = pos[dir[1]] + dir[2]
			node = minetest.get_node(pos)
		until node.name ~= "pump:pipe"
		set_data(old_pos, data)
		if node.name == "air" then
			minetest.set_node(pos, {name = "pump:pipe"})
			return
		end
		local sof, l = is_liquid(pos)
		if not sof then
			return
		end
		data.liquid = data.liquid or l
		if data.liquid ~= l then
			data.mode = "error"
			set_data(old_pos, data)
			return
		end
		if sof == "flowing" then
			minetest.set_node(pos, {name = "pump:pipe"})
			return
		end
		data.mode = "pump"
		set_data(old_pos, data, true)
		step(old_pos, data.mode)
	elseif data.mode == "error" then
		minetest.chat_send_all("error")
	elseif data.mode == "pump" then
		if not data.liquid then
			data.mode = "error"
			set_data(pos, data)
			return
		end
		local dstpos = vector.new(pos)
		dstpos[dir[1]] = dstpos[dir[1]] - dir[2]
		if minetest.get_node(dstpos).name ~= "air" then
			return
		end
		local srcpos = vector.new(pos)
		data.pipe_length = data.pipe_length or 0
		srcpos[dir[1]] = srcpos[dir[1]] + (data.pipe_length * dir[2])
		local node = minetest.get_node(srcpos)
		while node.name == "pump:pipe" do
			data.pipe_length = data.pipe_length + 1
			srcpos[dir[1]] = srcpos[dir[1]] + dir[2]
			node = minetest.get_node(srcpos)
		end
		set_data(pos, data)
		if node.name ~= liquids[data.liquid].source then
			data.mode = "extend"
			data.pipe_length = data.pipe_length - 1
			set_data(pos, data, true)
			step(pos)
			return
		end
		srcpos = get_liquid_pos(srcpos, data.liquid, dir)
		minetest.remove_node(srcpos)
		minetest.set_node(dstpos, {name = liquids[data.liquid].source})
	end
end

local function remove_pipes(pos, dir)
	pos[dir[1]] = pos[dir[1]] + dir[2]
	minetest.after(0.4, function(pos)
		if minetest.get_node(pos).name == "pump:pipe" then
			minetest.remove_node(pos)
		end
	end, pos)
end

local function make_formspec(data)
	local dir_abs = math.abs(data.dir)
	return "size[3,2]"..
		"checkbox[1,1;activated;activated;"..data.activated.."]"..
		"dropdown[0,0;0.5;dira;x,y,z;"..dir_abs.."]"..
		"dropdown[1,0;0.5;dirb;+,-;"..((data.dir/dir_abs > 0 and 1) or 2).."]"
end

minetest.register_node("pump:pump", {
	description = "Pump",
	tiles = {"default_steel_block.png^pump_side.png"},
	groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2},
	sounds = default.node_sound_wood_defaults(),
	on_construct = function(pos)
		local data = {
			mode = "extend",
			dir = -2,
			pipe_length = 0,
			activated = "false",
		}
		data.formspec = make_formspec(data)
		set_data(pos, data, true)
	end,
	on_receive_fields = function(pos, formanme, fields, sender)
		print(dump(fields))
		local data = get_data(pos)
		if fields.activated then
			data.activated = fields.activated
		end
		if fields.dira then
			local xyz = vector.new(1, 2, 3)
			data.dir = data.dir/math.abs(data.dir) * xyz[fields.dira]
		end
		if fields.dirb then
			data.dir = math.abs(data.dir) * (fields.dirb == "+" and 1) or -1
		end
		data.formspec = make_formspec(data)
		set_data(pos, data, true)
	end,
	on_punch = function(pos, node, puncher, pointed_thing)
		step(pos)
	end,
	on_destruct = function(pos)
		local data = get_data(pos)
		local xyz = {"x", "y", "z"}
		data.dir = data.dir or -2
		local dir = math.abs(data.dir)
		dir = {xyz[dir], data.dir/dir}
		remove_pipes(pos, dir)
		set_data(pos, {}, true)
	end,
})

minetest.register_node("pump:pipe", {
	description = "You hacker you!",
	tiles = {"pump_pipe_side.png"},
	groups = {snappy = 2, choppy = 2, oddly_breakable_by_hand = 2,
		not_in_creative_inventory = 1},
	sounds = default.node_sound_wood_defaults(),
	drop = "",
	on_destruct = function(pos)
		local dir = {"y", -1} -- Just some default values.
		local pipe_near = minetest.find_node_near(pos, 1, "pump:pipe")
		if not pipe_near then -- Set pipe_length to 0 if it's only one pipe.
			local pump_near = minetest.find_node_near(pos, 1, "pump:pump")
			if not pump_near then
				return
			end
			local data = get_data(pump_near)
			data.pipe_length = 0
			data.mode = "extend"
			set_data(pos, data, true)
			return
		end
		local posdif = vector.subtract(pos, pipe_near)
		for p, v in pairs(posdif) do
			if v ~= 0 then
				dir[1] = p
				dir[2] = -1 * v
				break
			end
		end
		-- Remove pipes away from pump.
		local pu = vector.new(pos)
		local pumppos
		repeat
			pu[dir[1]] = pu[dir[1]] + dir[2]
			local node = minetest.get_node(pu)
			if node.name ~= "pump:pipe" then
				if node.name == "pump:pump" then
					pumppos = pu
					dir[2] = -1 * dir[2]
				end
				break
			end
		until false
		remove_pipes(vector.new(pos), dir)
		local i
		if not pumppos then
			pumppos = vector.new(pos)
			i = -1
			local node
			repeat
				i = i + 1
				pumppos[dir[1]] = pumppos[dir[1]] - dir[2]
				node = minetest.get_node(pumppos)
			until node.name ~= "pump:pipe"
			if node.name ~= "pump:pump" then
				return
			end
		else
			i = vector.distance(pos,pumppos) - 1
		end
		local data = get_data(pumppos)
		data.pipe_length = i
		data.mode = "extend"
		set_data(pumppos, data, true)
	end,
})


local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "["..modname.."] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
