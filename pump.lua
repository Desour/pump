local function table_has(t, v, v_is_vector)
	if type(t) ~= "table" then
		return
	end
	for i = 1, #t do
		if t[i] == v or (v_is_vector and vector.equals(t[i], v)) then
			return true
		end
	end
	return false
end

local function get_connected1(start_pos, node_names, poss) -- TODO: use voxel manipulation
	local poss = poss or {}
	local distances = {}
	local xyz = {"x", "y", "z", "x", "y", "z"}
	for i = 1, 6 do
		local pos = vector.new(start_pos)
		local diff = 1
		if i <= 3 then
			diff = -1
		end
		pos[xyz[i]] = pos[xyz[i]] + diff
		if not table_has(poss, pos, true) and table_has(node_names, minetest.get_node(pos).name) then
			distances[pos] = vector.distance(start_pos, pos)
			poss[#poss+1] = pos
			poss = get_connected1(pos, node_names, poss)
		end
	end
	return poss, distances
end


minetest.register_craftitem("technic:pump_test1",{
	description = "Pumptester",
	inventory_image = "default_tool_steelshovel.png",
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		minetest.chat_send_all("bla")
		local pos = pointed_thing.under
		local poss, distances = get_connected1(pos, {minetest.get_node(pos).name})
		local count = #poss
		--~ minetest.chat_send_all(dump(poss))
		minetest.chat_send_all(count or "mhm")
		local farest = 0
		local farest_pos
		for p, d in pairs(distances) do
			if d > farest then
				farest = d
				farest_pos = p
			end
		end
		minetest.chat_send_all(minetest.pos_to_string(farest_pos))
	end,
})


local function get_connected(start_pos, node_names)
	local node_ids = {}
	for i = 1, #node_names do
		node_ids[i] = minetest.get_content_id(node_names[i])
	end
	local manip = minetest.get_voxel_manip()
	local map = {}
	local pmin, pmax = manip:read_from_map(vector.add(start_pos, -256), vector.add(start_pos, 256))
	manip:get_data(map)
	--~ VoxelArea:new{MinEdge=pmin, MaxEdge=pmax}
	local count = 0
	for k = 1, #node_ids do
		for i = 1, #map do
			if map[i] == node_ids[k] then
				count = count + 1
			end
		end
	end
	minetest.chat_send_all(count)
end


local function run(pos, node)
	local liquids = {"default:lava_source", "default:lava_flowing"}
	local meta = minetest.get_meta(pos)
	--~ minetest.chat_send_all("run")
	meta:set_int("LV_EU_demand", 600)
	--~ minetest.chat_send_all(meta:get_int("LV_EU_input"))
	meta:set_string("infotext", "Pump")
end

minetest.register_node("technic:pump_pipe", {
	description = "You hacker you!",
	tiles = {"default_dirt.png^default_leaves.png"},
	groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2},
	sounds = default.node_sound_wood_defaults(),
	drop = "",
})

minetest.register_node("technic:pump", {
	description = "Pump",
	tiles = {"default_dirt.png^default_glass.png"},
	groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2,
		technic_machine=1, technic_lv=1},
	connect_sides = {"all"},
	sounds = default.node_sound_wood_defaults(),
	--~ on_construct = function(pos)
	--~ end,
	--~ on_receive_fields = function(pos, formanme, fields, sender)
	--~ end,
	technic_run = run,
	technic_on_disable = function(pos, node)
		local meta = minetest.get_meta(pos)
		meta:set_int("LV_EU_demand", 0)
	end,
})

technic.register_machine("LV", "technic:pump", technic.receiver)


