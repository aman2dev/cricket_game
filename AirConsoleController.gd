extends Node3D

## AirConsoleController.gd
## Serves as the networking hub. Receives smartphone WebSocket packages and channels
## sensor data to either the Batting Impact system (BatMesh) or the Bowler Input Receiver.

@export var cricket_bat_node: Node3D
@export var pitcher_pos := Vector3(0, 1.2, -18)
@export var batter_pos  := Vector3(0, 1.2,   0)

# Networking
var ws_client: WebSocketPeer = WebSocketPeer.new()
var ws_connected: bool = false
var active_ball: RigidBody3D = null

# Bowling Windmill Gesture Detection
var last_bowling_pitch: float = 0.0
var last_bowling_time: float = 0.0
const BOWLING_SPEED_THRESHOLD: float = 5.0 # Rads/sec threshold for fast change

func _ready() -> void:
	if not cricket_bat_node:
		# Auto-detect a child node carrying the calibration/batting script if not assigned
		for child in get_children():
			if child.has_method("on_sensor_data_received"):
				cricket_bat_node = child
				break
		if not cricket_bat_node:
			cricket_bat_node = self

	Engine.physics_ticks_per_second = 120

	# Connect to local Node.js relay server
	var ws_url = "ws://localhost:8000"
	print("[Network] Connecting to WebSocket: ", ws_url)
	if ws_client.connect_to_url(ws_url) != OK:
		print("[Network] WebSocket connection failed to initialize.")

func _process(delta: float) -> void:
	# Keyboard Fallbacks (For development/testing)
	if Input.is_action_just_pressed("ui_accept"):
		if GameManager.current_state == GameManager.State.TUTORIAL:
			GameManager.change_state(GameManager.State.BOWLER_RUNUP)
		elif GameManager.current_state == GameManager.State.BOWLER_RUNUP:
			pitch_ball(1.0, 0.0)

	ws_client.poll()
	var state = ws_client.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not ws_connected:
			ws_connected = true
			print("[Network] WebSocket connection opened successfully.")
		while ws_client.get_available_packet_count() > 0:
			_parse_message(ws_client.get_packet().get_string_from_utf8())

	elif state == WebSocketPeer.STATE_CLOSED and ws_connected:
		ws_connected = false
		print("[Network] WebSocket disconnected. Retrying in 2 seconds...")
		ws_client.connect_to_url("ws://localhost:8000")

func _parse_message(data_str: String) -> void:
	var json = JSON.new()
	if json.parse(data_str) != OK:
		return

	var data = json.get_data()

	if typeof(data) == TYPE_STRING:
		match data:
			"CALIBRATE":
				if cricket_bat_node and cricket_bat_node.has_method("calibrate_stance"):
					cricket_bat_node.calibrate_stance()
				if GameManager.current_state == GameManager.State.TUTORIAL:
					GameManager.change_state(GameManager.State.BOWLER_RUNUP)
			"PITCH":
				if GameManager.current_state == GameManager.State.BOWLER_RUNUP:
					pitch_ball(1.0, randf_range(-0.4, 0.4))

	elif typeof(data) == TYPE_DICTIONARY:
		if data.has("x") and data.has("y") and data.has("z") and data.has("w"):
			var x = float(data.x)
			var y = float(data.y)
			var z = float(data.z)
			var w = float(data.w)
			
			# 1. Forward raw orientation to Batting logic
			if cricket_bat_node and cricket_bat_node.has_method("on_sensor_data_received"):
				cricket_bat_node.on_sensor_data_received(x, y, z, w)
			
			# 2. Forward sensor values to Bowler Input logic during bowler phase
			if GameManager.current_state == GameManager.State.BOWLER_RUNUP:
				_process_bowling_input(x, y, z, w)

## Bowler Input Receiver: Monitors fast pitch axis rotation (windmill gesture)
func _process_bowling_input(x: float, y: float, z: float, w: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var dt = current_time - last_bowling_time
	
	var q = Quaternion(x, y, z, w)
	# Extract Euler pitch angle (rotation around phone's local X-axis)
	var euler = q.get_euler()
	var current_pitch = euler.x
	
	if dt > 0.005 and last_bowling_time > 0.0:
		var pitch_speed = abs(current_pitch - last_bowling_pitch) / dt
		
		# Detect rapid rotation (fast forward flip of the wrist/arm)
		if pitch_speed > BOWLING_SPEED_THRESHOLD:
			# Map angular velocity to a velocity multiplier (1.0 = base speed, up to 2.2)
			var speed_multiplier = clamp(pitch_speed / 8.0, 0.9, 2.2)
			# Add a spin sweep curve based on yaw tilt
			var spin_offset = clamp(euler.y * 0.4, -0.6, 0.6)
			
			print("[BowlingNetwork] Windmill swing detected! Angular Speed: ", pitch_speed, " -> Ball Speed Mult: ", speed_multiplier)
			pitch_ball(speed_multiplier, spin_offset)
			
	last_bowling_pitch = current_pitch
	last_bowling_time = current_time

## Instances a dynamic Ball.gd node in the scene and initiates launch impulse
func pitch_ball(speed_multiplier: float, spin_offset: float) -> void:
	# Clean up previous ball if still flying
	if active_ball and is_instance_valid(active_ball):
		active_ball.queue_free()
		
	# Instance new RigidBody3D and assign Ball.gd script dynamically
	active_ball = RigidBody3D.new()
	active_ball.set_script(preload("res://Ball.gd"))
	active_ball.name = "CricketBall"
	active_ball.position = pitcher_pos
	active_ball.mass = 0.16
	
	var mat = PhysicsMaterial.new()
	mat.bounce = 0.65
	active_ball.physics_material_override = mat
	
	var col = CollisionShape3D.new()
	var sph = SphereShape3D.new()
	sph.radius = 0.15
	col.shape = sph
	active_ball.add_child(col)
	
	var mesh_inst = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.15
	sphere_mesh.height = 0.3
	
	var ball_mat = StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.85, 0.1, 0.15, 1.0) # Stylized beach red ball
	ball_mat.roughness = 0.15
	sphere_mesh.material = ball_mat
	mesh_inst.mesh = sphere_mesh
	active_ball.add_child(mesh_inst)
	
	# Add to main scene root
	get_parent().add_child(active_ball)
	
	# Launch the ball pitch
	active_ball.launch_pitch(speed_multiplier, spin_offset)
