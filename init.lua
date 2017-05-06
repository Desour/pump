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

local function get_connected(startpos, nodes, connected, VoxelManip, minp, maxp, hashed_pos)
	local node = VoxelManip:get_node_at(startpos)
	connected[hashed_pos] = nodes[node.name] or false
	if not nodes[node.name] then
		return connected
	end
	local xyz = {"x", "y", "z"}
	for p = 1, 3 do
		for i = 1, -1, -2 do
			local pos = vector.new(startpos)
			pos[xyz[p]] = pos[xyz[p]] + i
			hashed_pos = minetest.hash_node_position(pos)
			if connected[hashed_pos] == nil and pos[xyz[p]] > minp[xyz[p]] and
					pos[xyz[p]] < maxp[xyz[p]] then
				connected = get_connected(pos, nodes, connected,
						VoxelManip, minp, maxp, hashed_pos)
			end
			if p == 2 then
				break
			end
		end
	end
	return connected
end

-- Returns the pos of the liquid source that should be pumped next.
local function get_liquid_pos(pos, liquid)
	-- get all (to side or up) connected
	local VoxelManip = minetest.get_voxel_manip()
	local minp, maxp = VoxelManip:read_from_map(vector.add(pos, -50), vector.add(pos, 50))
	local connected_o = get_connected(pos, {
		[liquids[liquid].source] = "s",
		[liquids[liquid].flowing] = "f",
	}, {}, VoxelManip, minp, maxp, minetest.hash_node_position(pos))
	local connected = {}
	for h, t in pairs(connected_o) do
		if t == "s" then
			connected[#connected+1] = minetest.get_position_from_hash(h)
		end
	end
-- choose the highest ones
	local outposss = {}
	for i = 1, #connected do
		if not outposss[1] or outposss[1].y < connected[i].y then
			outposss = {connected[i]}
		elseif outposss[1].y == connected[i].y then
			outposss[#outposss+1] = connected[i]
		end
	end
	-- choose the ones that are most far away
	local outposs = {}
	local maxdist = 0
	for i = 1, #outposss do
		local dist = vector.distance(pos, outposss[i])
		if dist >= maxdist then
			maxdist = dist
			outposs[#outposs+1] = outposss[i]
		end
	end
	-- if it are more than one, choose by random
	local outpos = outposs[math.random(#outposs)]
	return outpos
end

local function step(pos)
	local data = get_data(pos)
	if data.mode == "extend" then
		local old_pos = vector.new(pos)
		data.pipe_length = data.pipe_length or 0
		pos.y = pos.y - data.pipe_length
		local node
		repeat
			data.pipe_length = data.pipe_length + 1
			pos.y = pos.y - 1
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
		dstpos.y = dstpos.y + 1
		if minetest.get_node(dstpos).name ~= "air" then
			return
		end
		local srcpos = vector.new(pos)
		data.pipe_length = data.pipe_length or 0
		srcpos.y = srcpos.y - data.pipe_length
		local node = minetest.get_node(srcpos)
		while node.name == "pump:pipe" do
			data.pipe_length = data.pipe_length + 1
			srcpos.y = srcpos.y - 1
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
		srcpos = get_liquid_pos(srcpos, data.liquid)
		minetest.remove_node(srcpos)
		minetest.set_node(dstpos, {name = liquids[data.liquid].source})
	end
end

local function remove_pipes(pos)
	pos.y = pos.y - 1
	minetest.after(0.4, function(pos)
		if minetest.get_node(pos).name == "pump:pipe" then
			minetest.remove_node(pos)
		end
	end, pos)
end

minetest.register_node("pump:pump", {
	description = "Pump",
	tiles = {"default_steel_block.png^pump_side.png"},
	groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2},
	sounds = default.node_sound_wood_defaults(),
	on_construct = function(pos)
		set_data(pos, {mode = "extend", dir = "-y", pipe_length = 0}, true)
	end,
	--~ on_receive_fields = function(pos, formanme, fields, sender) -- TODO
	--~ end,
	on_punch = function(pos, node, puncher, pointed_thing)
		step(pos)
	end,
	on_destruct = function(pos)
		remove_pipes(pos)
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
		remove_pipes(vector.new(pos))
		local i = -1
		local node
		repeat
			i = i + 1
			pos.y = pos.y + 1
			node = minetest.get_node(pos)
		until node.name ~= "pump:pipe"
		if node.name ~= "pump:pump" then
			return
		end
		local data = get_data(pos)
		data.pipe_length = i
		data.mode = "extend"
		set_data(pos, data)
	end,
})


local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "["..modname.."] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
