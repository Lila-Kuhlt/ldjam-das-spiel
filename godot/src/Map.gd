extends Node2D

const WORLD_GEN_ENABLE: bool = false

export var grass_tile_ratio: float = 0.4;
export var tile_count_w: int = 51;
export var tile_count_h: int = 51;

onready var l_background: TileMap = $BackgroundLayer
onready var l_ground: TileMap = $GroundLayer
onready var l_foreground: TileMap = $ForegroundLayer
onready var l_building: TileMap = $BuildingLayer
onready var l_nav: TileMap = $NavigationLayer
onready var l_preview: TileMap = $BuildPreviewLayer

onready var wg = preload("res://src/WorldGen.gd")

onready var farmland_id: int = l_preview.tile_set.find_tile_by_name("FarmSoil")
onready var wasteland_id: int = l_ground.tile_set.find_tile_by_name("Wasteland")
onready var water_id: int = l_ground.tile_set.find_tile_by_name("Water")
onready var stone_id: int = l_foreground.tile_set.find_tile_by_name("Stone")
onready var tree_id: int = l_foreground.tile_set.find_tile_by_name("Tree")

func _ready():
	generate_bg_layer()
	if WORLD_GEN_ENABLE:
		l_ground.clear()
		l_foreground.clear()
		var gen = wg.Generator.new(tile_count_w, tile_count_h)
		gen.generate()
		for y in range(tile_count_h):
			for x in range(tile_count_w):
				var tile = gen.tiles[x + y * tile_count_w]
				match tile:
					wg.VTile.Barn: pass # TODO
					wg.VTile.Wasteland: l_ground.set_cell(x, y, wasteland_id)
					wg.VTile.WastelandStone:
						l_ground.set_cell(x, y, wasteland_id)
						l_foreground.set_cell(x, y, stone_id)
					wg.VTile.Grass: pass
					wg.VTile.GrassStone: l_foreground.set_cell(x, y, stone_id)
					wg.VTile.Tree: l_foreground.set_cell(x, y, tree_id)
					wg.VTile.Pond: l_ground.set_cell(x, y, water_id)
					wg.VTile.River: l_ground.set_cell(x, y, water_id)
		l_ground.update_bitmask_region(Vector2(0, 0), Vector2(tile_count_w, tile_count_h))
		l_foreground.update_bitmask_region(Vector2(0, 0), Vector2(tile_count_w, tile_count_h))
	set_invisible_navigation_tiles()
	$Spawner.set_map(self)
	l_building.clear()
	l_preview.clear()

func generate_bg_layer():
	l_background.clear()
	for y in range(tile_count_h):
		for x in range(tile_count_w):
			var id = int(randf() > grass_tile_ratio)
			l_background.set_cell(x, y, 0, false, false, false, Vector2(id, 0))

func set_invisible_navigation_tiles():
	var tile_nav_id = l_nav.tile_set.find_tile_by_name("NavigationHack")

	# Find the bounds of the tilemap (there is no 'size' property available)
	var bounds_min := Vector2.ZERO
	var bounds_max := Vector2.ZERO
	for pos in l_ground.get_used_cells() + l_foreground.get_used_cells():
		if pos.x < bounds_min.x:
			bounds_min.x = int(pos.x)
		elif pos.x > bounds_max.x:
			bounds_max.x = int(pos.x)
		if pos.y < bounds_min.y:
			bounds_min.y = int(pos.y)
		elif pos.y > bounds_max.y:
			bounds_max.y = int(pos.y)

	# Iterate all cells within bounds
	for x in range(bounds_min.x, bounds_max.x):
		for y in range(bounds_min.y, bounds_max.y):
			var has_obstacle := has_tile_collider(x, y)
			l_nav.set_cell(x, y, -1 if has_obstacle else tile_nav_id)

	# Force the navigation mesh to update immediately
	l_nav.update_dirty_quadrants()

func has_tile_collider(x: int, y: int) -> bool:
	# detects if the position has an obstacle (forest, rock, water, ...)
	for tile_map in [l_foreground, l_ground]:
		var tile_id = tile_map.get_cell(x, y)
		if (tile_id != -1 and
			tile_id in tile_map.tile_set.get_tiles_ids() and
			tile_map.tile_set.tile_get_shape_count(tile_id) > 0
		):
			return true
	return false

func world_to_map(world_pos: Vector2) -> Vector2:
	return l_building.world_to_map(world_pos)

func map_to_world(map_pos: Vector2) -> Vector2:
	return l_building.map_to_world(map_pos)

func snap_to_grid_center(global : Vector2):
	var map_pos = (l_ground.world_to_map(global) * 32)
	map_pos += (l_ground.cell_size / 2)
	return map_pos

func building_place(world_pos: Vector2, remove = false):
	var map_pos = l_building.world_to_map(world_pos)
	if remove:
		l_building.set_cellv(map_pos, TileMap.INVALID_CELL)
	else:
		var occupied = l_building.tile_set.find_tile_by_name("Occupied")
		l_building.set_cellv(map_pos, occupied)

func can_place_building_at(world_pos: Vector2) -> bool:
	return can_place_building_at_map_pos(world_to_map(world_pos))

func can_place_building_at_map_pos(map_pos: Vector2) -> bool:
	if l_building.get_cellv(map_pos) != TileMap.INVALID_CELL:
		# position already has a building
		return false
	return not has_tile_collider(int(map_pos.x), int(map_pos.y))

func is_building_at(world_pos: Vector2) -> bool:
	var map_pos = l_building.world_to_map(world_pos)
	var tile_id = l_building.get_cellv(map_pos)

	return tile_id != TileMap.INVALID_CELL

func is_ground_at(map_pos: Vector2, ground: String) -> bool:
	return l_ground.get_cellv(map_pos) == l_ground.tile_set.find_tile_by_name(ground)

func _get_positions_around_tower(map_pos: Vector2, radius: int):
	var positions = []
	var r2 := radius * 2 + 1
	for _dy in range(r2):
		for _dx in range(r2):
			var d := Vector2(_dx - radius, _dy - radius)
			if (d != Vector2(0, 0)
				and can_place_building_at_map_pos(map_pos + d)
				and not is_ground_at(map_pos + d, "Wasteland")
			):
				positions.append(map_pos + d)
	return positions

func set_ground_around_tower(map_pos: Vector2, radius: int):
	for pos in _get_positions_around_tower(map_pos, radius):
		l_ground.set_cellv(pos, farmland_id)
	var rvec := Vector2(radius, radius)
	l_ground.update_bitmask_region(map_pos - rvec, map_pos + rvec)

func update_preview_ground(world_pos: Vector2, radius: int):
	l_preview.clear()
	var map_pos := world_to_map(world_pos)
	for pos in _get_positions_around_tower(map_pos, radius):
		l_preview.set_cellv(pos, farmland_id)
	var rvec := Vector2(radius, radius)
	l_preview.update_bitmask_region(map_pos - rvec, map_pos + rvec)

func remove_preview_ground():
	l_preview.clear()
