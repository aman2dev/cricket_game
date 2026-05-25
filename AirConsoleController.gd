extends Node3D

@export var cricket_bat_node: Node3D
@export var smoothing_speed: float = 40.0

# Axis Inversion settings to match playing facing the screen
@export var invert_x: bool = false
@export var invert_y: bool = true
@export var invert_z: bool = true

# Native Godot WebSocket Client
var ws_client: WebSocketPeer = WebSocketPeer.new()
var ws_connected: bool = false

var raw_calibration_offset: Quaternion = Quaternion.IDENTITY
var incoming_raw_quaternion: Quaternion = Quaternion.IDENTITY

var debug_label: Label
var score_label: Label

# Gameplay variables
var runs: int = 0
var wickets: int = 0
var balls_pitched: int = 0

# Spawn coordinates
var pitcher_pos = Vector3(0, 1.2, -18)
var batter_pos = Vector3(0, 1.2, 0)
var active_ball: RigidBody3D = null

func _ready():
	if not cricket_bat_node:
		cricket_bat_node = self
		
	Engine.physics_ticks_per_second = 120
		
	# Screen overlay debug labels
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	debug_label = Label.new()
	debug_label.text = "Connecting to WebSocket server..."
	
	var settings = LabelSettings.new()
	settings.font_size = 20
	settings.font_color = Color(0.0, 1.0, 0.0, 1.0)
	settings.outline_size = 4
	settings.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	debug_label.label_settings = settings
	debug_label.position = Vector2(20, 20)
	canvas_layer.add_child(debug_label)

	# Score Board HUD
	score_label = Label.new()
	score_label.text = "SCORE: 0 Runs | Wickets: 0 | Balls: 0\n[Spacebar or Phone Tap to Pitch]"
	var score_settings = LabelSettings.new()
	score_settings.font_size = 32
	score_settings.font_color = Color(1.0, 0.84, 0.0, 1.0)
	score_settings.outline_size = 6
	score_settings.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	score_label.label_settings = score_settings
	score_label.position = Vector2(20, 80)
	canvas_layer.add_child(score_label)

	# Connect to local WebSocket server
	var ws_url = "ws://localhost:8000"
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		if window:
			var host = window.location.host
			var protocol = "ws:"
			if window.location.protocol == "https:":
				protocol = "wss:"
			ws_url = protocol + "//" + host
			
	print("Connecting to WebSocket URL: ", ws_url)
	var err = ws_client.connect_to_url(ws_url)
	if err != OK:
		debug_label.text = "Connection error: " + str(err)

func _process(delta):
	# Handle spacebar pitching
	if Input.is_action_just_pressed("ui_accept"):
		pitch_ball()
		
	# Poll WebSocket events
	ws_client.poll()
	var state = ws_client.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not ws_connected:
			ws_connected = true
			debug_label.text = "WebSocket Connected!"
			
		while ws_client.get_available_packet_count() > 0:
			var packet = ws_client.get_packet()
			var data_str = packet.get_string_from_utf8()
			_parse_message(data_str)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if ws_connected:
			ws_connected = false
			debug_label.text = "WebSocket Disconnected. Reconnecting..."
			ws_client.connect_to_url("ws://localhost:8000")
			
	if not cricket_bat_node:
		return
		
	# Compute corrected rotation
	var corrected_rotation = raw_calibration_offset.inverse() * incoming_raw_quaternion
	
	# Smoothly rotate the 3D bat AnimatableBody3D using Slerp
	cricket_bat_node.quaternion = cricket_bat_node.quaternion.slerp(corrected_rotation, delta * smoothing_speed)
	
	# Track the ball game logic
	if active_ball and is_instance_valid(active_ball):
		if active_ball.position.z > 3.0:
			if active_ball.linear_velocity.length() < 3.0 or active_ball.position.x < -2.0 or active_ball.position.x > 2.0:
				update_hud("Ball Dead")
				active_ball.queue_free()
				active_ball = null
			else:
				wickets += 1
				update_hud("WICKET! You missed it!")
				active_ball.queue_free()
				active_ball = null
		elif active_ball.position.z < -4.0 and active_ball.linear_velocity.z < -4.0:
			var distance = active_ball.position.distance_to(Vector3(0, 0, 0))
			if distance > 12.0:
				var hit_runs = 4
				if distance > 22.0:
					hit_runs = 6
				runs += hit_runs
				update_hud("SMASH! You scored " + str(hit_runs) + " Runs!")
				active_ball.queue_free()
				active_ball = null

func _parse_message(data_str: String):
	var json = JSON.new()
	var error = json.parse(data_str)
	if error == OK:
		var data = json.get_data()
		
		# 1. Handle String Command
		if typeof(data) == TYPE_STRING:
			if data == "CALIBRATE":
				raw_calibration_offset = incoming_raw_quaternion
				debug_label.text = "CALIBRATE RECEIVED!"
				print("Calibration Offset Calibrated: ", raw_calibration_offset)
			elif data == "PITCH":
				pitch_ball()
				
		# 2. Handle Quaternion payload object
		elif typeof(data) == TYPE_DICTIONARY:
			if data.has("x") and data.has("y") and data.has("z") and data.has("w"):
				# Apply axis inversion settings
				var q_x = -float(data.x) if invert_x else float(data.x)
				var q_y = -float(data.y) if invert_y else float(data.y)
				var q_z = -float(data.z) if invert_z else float(data.z)
				var q_w = float(data.w)
				
				incoming_raw_quaternion = Quaternion(q_x, q_y, q_z, q_w)
				
				# Display values in debug overlay
				debug_label.text = (
					"Controller Connected\n" +
					"X: " + str(snapped(incoming_raw_quaternion.x, 0.01)) + "\n" +
					"Y: " + str(snapped(incoming_raw_quaternion.y, 0.01)) + "\n" +
					"Z: " + str(snapped(incoming_raw_quaternion.z, 0.01)) + "\n" +
					"W: " + str(snapped(incoming_raw_quaternion.w, 0.01)) + "\n" +
					"Bat Rot: " + str(cricket_bat_node.rotation)
				)
	else:
		debug_label.text = "JSON Parse Error: " + json.get_error_message()

func pitch_ball():
	if active_ball and is_instance_valid(active_ball):
		active_ball.queue_free()
		
	balls_pitched += 1
	update_hud("Ball Pitching...")

	active_ball = RigidBody3D.new()
	active_ball.position = pitcher_pos
	
	active_ball.mass = 0.16
	var ball_material = PhysicsMaterial.new()
	ball_material.bounce = 0.65
	active_ball.physics_material_override = ball_material
	
	var col = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.15
	col.shape = sphere_shape
	active_ball.add_child(col)
	
	var mesh_inst = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.15
	sphere_mesh.height = 0.3
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.1, 0.1, 1.0)
	material.roughness = 0.2
	sphere_mesh.material = material
	mesh_inst.mesh = sphere_mesh
	active_ball.add_child(mesh_inst)
	
	get_parent().add_child(active_ball)
	
	var speed = randf_range(16.0, 20.0)
	var direction = (batter_pos - pitcher_pos).normalized()
	direction.y += 0.08
	
	active_ball.linear_velocity = direction * speed

func update_hud(status_msg = ""):
	var msg = "SCORE: " + str(runs) + " Runs | Wickets: " + str(wickets) + " | Balls: " + str(balls_pitched)
	if status_msg != "":
		msg += "\n[" + status_msg + "]"
	else:
		msg += "\n[Spacebar or Phone Tap to Pitch]"
	score_label.text = msg
