class_name LookProfile
extends RefCounted
## Applies a visual profile (data/look/*.json): environment, sun, grading and
## the gameplay camera. The WE look comes from the whole scene
## (player + kit + field + camera + light + shadow), so all of it is data
## that can be calibrated side by side with reference captures.

const DEFAULT := "we2002_hd"


static func load_profile(id := DEFAULT) -> Dictionary:
	var data: Variant = DataLoader.load_json("look/%s.json" % id)
	return data if data is Dictionary else {}


static func apply_to_scene(root: Node, profile: Dictionary) -> void:
	var env_cfg: Dictionary = profile.get("environment", {})
	var world := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null:
		world = WorldEnvironment.new()
		world.name = "WorldEnvironment"
		root.add_child(world)
	world.environment = build_environment(env_cfg)

	var sun_cfg: Dictionary = profile.get("sun", {})
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		root.add_child(sun)
	sun.light_color = Color.html(str(sun_cfg.get("color", "#ffffff")))
	sun.light_energy = float(sun_cfg.get("energy", 1.0))
	sun.rotation = Vector3(deg_to_rad(float(sun_cfg.get("pitch_deg", -50.0))), deg_to_rad(float(sun_cfg.get("yaw_deg", -35.0))), 0.0)
	sun.shadow_enabled = true
	sun.shadow_opacity = float(sun_cfg.get("shadow_opacity", 1.0))
	sun.directional_shadow_max_distance = float(sun_cfg.get("shadow_max_distance", 120.0))


static func build_environment(cfg: Dictionary) -> Environment:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color.html(str(cfg.get("sky_top", "#4f7fc4")))
	sky_mat.sky_horizon_color = Color.html(str(cfg.get("sky_horizon", "#b5c7d8")))
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color.html(str(cfg.get("sky_ground", "#3a4a3a")))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(cfg.get("ambient_energy", 0.6))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if cfg.get("tonemap", "filmic") == "filmic" else Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(cfg.get("exposure", 1.0))
	env.tonemap_white = float(cfg.get("white", 6.0))
	env.ssao_enabled = bool(cfg.get("ssao", true))
	env.ssao_radius = float(cfg.get("ssao_radius", 1.0))
	env.ssao_intensity = float(cfg.get("ssao_intensity", 1.5))
	env.adjustment_enabled = bool(cfg.get("adjustments", true))
	env.adjustment_brightness = float(cfg.get("brightness", 1.0))
	env.adjustment_contrast = float(cfg.get("contrast", 1.0))
	env.adjustment_saturation = float(cfg.get("saturation", 1.0))
	return env


static func apply_camera(camera: WECamera, profile: Dictionary) -> void:
	var c: Dictionary = profile.get("camera", {})
	camera.fov = float(c.get("fov", camera.fov))
	camera.height = float(c.get("height", camera.height))
	camera.distance = float(c.get("distance", camera.distance))
	camera.lead = float(c.get("lead", camera.lead))
	camera.lead_speed = float(c.get("lead_speed", camera.lead_speed))
	camera.follow_speed = float(c.get("follow_speed", camera.follow_speed))
	camera.dead_zone = float(c.get("dead_zone", camera.dead_zone))


static func pitch_color(profile: Dictionary, key: String, fallback: Color) -> Color:
	var p: Dictionary = profile.get("pitch", {})
	return Color.html(str(p[key])) if p.has(key) else fallback
