extends Control

@onready var map_texture = $MapContainer
@onready var objects_container = $ObjectsContainer
@onready var links_container = $LinksContainer

var world_name = ""
var maps_data = {}

func load_world(selected_world):
	world_name = selected_world
	print("Initializing world:", world_name)
	load_world_data()

func load_world_data():
	var file_path = ProjectSettings.globalize_path("res://worlds/%s/maps.txt" % world_name)
	var file = FileAccess.open(file_path, FileAccess.READ)

	if file == null:
		print("Failed to open world data:", file_path)
		return

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue

		var data = line.split(",")
		if data.size() >= 5:
			var map_id = int(data[0])
			maps_data[map_id] = {
				"image": data[1].strip_edges(),
				"name": data[2].strip_edges(),
				"title": data[3].strip_edges(),
				"flags": int(data[4])
			}

	file.close()
	print("Loaded maps:", maps_data)

	if maps_data.size() > 0:
		var first_map_id = maps_data.keys().min()
		load_map(first_map_id)

func load_map(map_id):
	if not maps_data.has(map_id):
		print("Map ID not found:", map_id)
		return

	var map_info = maps_data[map_id]
	
	# Try to load X4 version first
	var base_path = "res://worlds/%s/maps/%s" % [world_name, map_info["image"]]
	var x4_path = base_path.replace(".jpg", "X4.jpg")
	
	var image_path = x4_path
	var texture = load(x4_path)
	
	if not texture:
		image_path = base_path
		texture = load(base_path)
		# Note: Would need to handle manual scaling here if needed
	
	if texture:
		map_texture.texture = texture
		print("Loaded map:", map_info["name"])
		load_world_objects(map_id)
		load_map_links(map_id)
	else:
		print("Failed to load map image:", image_path)

func load_world_objects(map_id):
	var map_info = maps_data.get(map_id)
	if not map_info:
		print("Invalid map ID:", map_id)
		return

	var map_name = map_info["image"].get_basename()
	var objects_texture_path = "res://worlds/%s/maps/objects.png" % world_name
	var obl_path = ProjectSettings.globalize_path("res://worlds/%s/maps/%s.obl" % [world_name, map_name])
	var obr_path = ProjectSettings.globalize_path("res://worlds/%s/maps/objects.obr" % world_name)

	# Load objects texture
	var objects_image = Image.load_from_file(objects_texture_path)
	if objects_image == null:
		print("⚠️ Missing objects texture:", objects_texture_path)
		return

	# Apply transparency mask
	var mask_color = objects_image.get_pixel(0, 0)
	objects_image.convert(Image.FORMAT_RGBA8)

	for y in range(objects_image.get_height()):
		for x in range(objects_image.get_width()):
			if objects_image.get_pixel(x, y) == mask_color:
				objects_image.set_pixel(x, y, Color(0, 0, 0, 0))

	var objects_texture = ImageTexture.create_from_image(objects_image)

	# Debug Map and Container Positions
	print("==== Debugging Map & Containers ====")
	print("Map Texture Position:", map_texture.position)
	print("Objects Container Position:", objects_container.position)
	print("====================================")

	# Clear existing objects
	for child in objects_container.get_children():
		child.queue_free()

	# Read object records from .obr
	# Read object records first with sanity checks
	var objectData = []
	var obr_file = FileAccess.open(obr_path, FileAccess.READ)
	if obr_file:
		for i in range(1024):
			var x1 = obr_file.get_32()
			var y1 = obr_file.get_32()
			var x2 = obr_file.get_32()
			var y2 = obr_file.get_32()
			
			# Sanity check to prevent garbage values
			if x2 < x1 or y2 < y1 or x1 < 0 or y1 < 0 or x2 > objects_image.get_width() or y2 > objects_image.get_height():
				print("⚠️ Skipping invalid object", i, "->", x1, y1, x2, y2)
				continue  # Ignore this object
			
			objectData.append({
				"x1": x1,
				"y1": y1,
				"x2": x2,
				"y2": y2
			})
		obr_file.close()


	# Read map links and create objects
	var obl_file = FileAccess.open(obl_path, FileAccess.READ)
	if obl_file:
		for i in range(256):
			var is_visible = obl_file.get_32()
			var image_id = obl_file.get_32()
			var x = obl_file.get_32()
			var y = obl_file.get_32()
			
			if is_visible and image_id >= 0 and image_id < objectData.size():
				var obj = objectData[image_id]
				var width = abs(obj["x2"] - obj["x1"])
				var height = abs(obj["y2"] - obj["y1"])

				# Debug Object Data
				print("Object %d: (%d, %d) - (%d, %d), Size: %dx%d" % [
					image_id, obj["x1"], obj["y1"], obj["x2"], obj["y2"], width, height
				])

				# Create object sprite from texture atlas
				var object_region = Rect2(obj["x1"], obj["y1"], width, height)
				var atlas_texture = AtlasTexture.new()
				atlas_texture.atlas = objects_texture
				atlas_texture.region = object_region

				var object_sprite = Sprite2D.new()
				object_sprite.texture = atlas_texture
				
				# Calculate corrected position
				var sprite_x = x * 4 - width / 2
				var sprite_y = y * 4 - height / 2 + 4

				# Adjust for map alignment
				var adjusted_position = Vector2(sprite_x, sprite_y) - map_texture.position

				# Debug position adjustments
				print("Object %d placed at Raw (%d, %d), Adjusted (%d, %d)" % [
					image_id, sprite_x, sprite_y, adjusted_position.x, adjusted_position.y
				])

				# Apply final position and scaling correction
				object_sprite.global_position = adjusted_position
				object_sprite.scale = Vector2(1.0, 1.0)  # Ensure no scaling issues
				
				objects_container.add_child(object_sprite)
		
		obl_file.close()

	print("✓ Finished placing objects for map", map_name)

func load_map_links(map_id):
	# Clear existing links
	for child in links_container.get_children():
		child.queue_free()

	var map_info = maps_data.get(map_id)
	if not map_info:
		print("Invalid map ID:", map_id)
		return

	var map_name = map_info["image"].get_basename()
	var obl_path = ProjectSettings.globalize_path("res://worlds/%s/maps/%s.obl" % [world_name, map_name])

	var obl_file = FileAccess.open(obl_path, FileAccess.READ)
	if obl_file == null:
		print("Failed to open map links for", map_name)
		return

	print("Loading map links from:", obl_path)

	while not obl_file.eof_reached():
		var link_data = [
			obl_file.get_32(),  # is_visible
			obl_file.get_32(),  # image_id
			obl_file.get_32(),  # x
			obl_file.get_32(),  # y
			obl_file.get_32(),  # Additional unused data
			obl_file.get_32()   # Additional unused data
		]

		var is_visible = link_data[0]
		var x = link_data[2]
		var y = link_data[3]

		if is_visible:
			var link_marker = Node2D.new()
			link_marker.position = Vector2(x, y)
			links_container.add_child(link_marker)

	obl_file.close()
	print("Loaded map links for", map_name)
