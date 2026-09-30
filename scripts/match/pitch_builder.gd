class_name PitchBuilder
extends RefCounted
## Builds a regulation 105×68 pitch with physical goals. Deliberately plain:
## stage 0 is about feel, not grass shaders.

const HALF_LENGTH := 52.5
const HALF_WIDTH := 34.0
const GOAL_HALF_WIDTH := 3.66
const GOAL_HEIGHT := 2.44
const GOAL_DEPTH := 2.0
const POST_RADIUS := 0.06
const LINE_WIDTH := 0.12

const LAYER_WORLD := 1
const LAYER_GOAL := 8


static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Pitch"
	parent.add_child(root)
	_ground(root)
	_stripes(root)
	_lines(root)
	for side: float in [-1.0, 1.0]:
		_goal(root, side)
	return root


static func _ground(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.8
	mat.bounce = 0.0
	body.physics_material_override = mat
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(170.0, 1.0, 120.0)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	root.add_child(body)

	var surround := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 400.0)
	surround.mesh = plane
	surround.position.y = -0.01
	surround.material_override = _mat(Color(0.11, 0.2, 0.1))
	root.add_child(surround)


static func _stripes(root: Node3D) -> void:
	var count := 14
	var w := HALF_LENGTH * 2.0 / count
	var light := _mat(Color(0.19, 0.4, 0.15))
	var dark := _mat(Color(0.16, 0.35, 0.13))
	for i in count:
		var stripe := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(w, HALF_WIDTH * 2.0 + 6.0)
		stripe.mesh = plane
		stripe.position = Vector3(-HALF_LENGTH + w * (i + 0.5), 0.0, 0.0)
		stripe.material_override = light if i % 2 == 0 else dark
		root.add_child(stripe)


static func _lines(root: Node3D) -> void:
	var white := _mat(Color(0.95, 0.95, 0.95), true)
	var hl := HALF_LENGTH
	var hw := HALF_WIDTH
	_line(root, white, Vector3(0, 0, -hw), hl * 2.0, LINE_WIDTH)
	_line(root, white, Vector3(0, 0, hw), hl * 2.0, LINE_WIDTH)
	_line(root, white, Vector3(-hl, 0, 0), LINE_WIDTH, hw * 2.0)
	_line(root, white, Vector3(hl, 0, 0), LINE_WIDTH, hw * 2.0)
	_line(root, white, Vector3.ZERO, LINE_WIDTH, hw * 2.0)
	_circle(root, white, Vector3.ZERO, 9.15)
	_spot(root, white, Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		# Penalty area 16.5 × 40.32, goal area 5.5 × 18.32.
		_box(root, white, side, 16.5, 20.16)
		_box(root, white, side, 5.5, 9.16)
		_spot(root, white, Vector3(side * (hl - 11.0), 0, 0))


static func _box(root: Node3D, m: Material, side: float, depth: float, half_w: float) -> void:
	var x_line := side * (HALF_LENGTH - depth)
	_line(root, m, Vector3(x_line, 0, 0), LINE_WIDTH, half_w * 2.0)
	for z: float in [-half_w, half_w]:
		_line(root, m, Vector3(side * (HALF_LENGTH - depth * 0.5), 0, z), depth, LINE_WIDTH)


static func _line(root: Node3D, m: Material, center: Vector3, size_x: float, size_z: float) -> void:
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size_x, 0.01, size_z)
	line.mesh = mesh
	line.position = center + Vector3(0, 0.006, 0)
	line.material_override = m
	root.add_child(line)


static func _circle(root: Node3D, m: Material, center: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - LINE_WIDTH * 0.5
	torus.outer_radius = radius + LINE_WIDTH * 0.5
	torus.rings = 96
	ring.mesh = torus
	ring.position = center + Vector3(0, 0.004, 0)
	ring.scale = Vector3(1.0, 0.08, 1.0)
	ring.material_override = m
	root.add_child(ring)


static func _spot(root: Node3D, m: Material, center: Vector3) -> void:
	var spot := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 0.01
	spot.mesh = cyl
	spot.position = center + Vector3(0, 0.006, 0)
	spot.material_override = m
	root.add_child(spot)


static func _goal(root: Node3D, side: float) -> void:
	var goal := StaticBody3D.new()
	goal.name = "GoalRight" if side > 0.0 else "GoalLeft"
	goal.collision_layer = LAYER_GOAL
	goal.collision_mask = 0
	root.add_child(goal)

	var frame_mat := PhysicsMaterial.new()
	frame_mat.bounce = 0.2
	frame_mat.friction = 0.3
	var net_mat := PhysicsMaterial.new()
	net_mat.bounce = 0.5
	net_mat.absorbent = true
	net_mat.friction = 1.0

	var white := _mat(Color.WHITE)
	var net_visual := _mat(Color(1, 1, 1, 0.25))
	net_visual.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_visual.cull_mode = BaseMaterial3D.CULL_DISABLED

	var x := side * (HALF_LENGTH + POST_RADIUS)
	var post_h := GOAL_HEIGHT + POST_RADIUS * 2.0
	for z: float in [-GOAL_HALF_WIDTH - POST_RADIUS, GOAL_HALF_WIDTH + POST_RADIUS]:
		_cylinder(goal, frame_mat, white, Vector3(x, post_h * 0.5, z), post_h, Vector3.ZERO)
	var bar_len := (GOAL_HALF_WIDTH + POST_RADIUS * 2.0) * 2.0
	_cylinder(goal, frame_mat, white, Vector3(x, GOAL_HEIGHT + POST_RADIUS, 0.0), bar_len, Vector3(PI * 0.5, 0, 0))

	var back_x := side * (HALF_LENGTH + GOAL_DEPTH)
	var mid_x := side * (HALF_LENGTH + GOAL_DEPTH * 0.5)
	_panel(goal, net_mat, net_visual, Vector3(back_x, GOAL_HEIGHT * 0.5, 0), Vector3(0.05, GOAL_HEIGHT, GOAL_HALF_WIDTH * 2.0))
	_panel(goal, net_mat, net_visual, Vector3(mid_x, GOAL_HEIGHT, 0), Vector3(GOAL_DEPTH, 0.05, GOAL_HALF_WIDTH * 2.0))
	for z: float in [-GOAL_HALF_WIDTH - 0.1, GOAL_HALF_WIDTH + 0.1]:
		_panel(goal, net_mat, net_visual, Vector3(mid_x, GOAL_HEIGHT * 0.5, z), Vector3(GOAL_DEPTH, GOAL_HEIGHT, 0.05))


static func _cylinder(body: StaticBody3D, pmat: PhysicsMaterial, vmat: Material, pos: Vector3, h: float, rot: Vector3) -> void:
	var holder := StaticBody3D.new()
	holder.collision_layer = LAYER_GOAL
	holder.collision_mask = 0
	holder.physics_material_override = pmat
	holder.position = pos
	holder.rotation = rot
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = POST_RADIUS
	cyl.height = h
	shape.shape = cyl
	holder.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = POST_RADIUS
	cm.bottom_radius = POST_RADIUS
	cm.height = h
	mesh.mesh = cm
	mesh.material_override = vmat
	holder.add_child(mesh)
	body.add_child(holder)


static func _panel(body: StaticBody3D, pmat: PhysicsMaterial, vmat: Material, pos: Vector3, size: Vector3) -> void:
	var holder := StaticBody3D.new()
	holder.collision_layer = LAYER_GOAL
	holder.collision_mask = 0
	holder.physics_material_override = pmat
	holder.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	holder.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = vmat
	holder.add_child(mesh)
	body.add_child(holder)


static func _mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
