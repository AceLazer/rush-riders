extends CharacterBody3D

#states
enum State { GROUNDED, AIRBORNE, WALLRUN, GRIND }
var current_state := State.GROUNDED



#lookin
@export_group("Camera")
@export_range(0.0, 1.0) var mouseSensitivity := 0.1
@export var tilt_camera := 15.0 # amount that we tilt the camera when wall riding

#movin
@export_group("Movement")
@export var move_speed := 8.0
@export var acceleration := 20.0
@export var rotation_speed := 12.0
@export var jump_impulse := 12.0 # how high we jump - is added to the velocity.y

#jump delays
@export var jump_buffer_time := 0.1  # How long to remember a jump press
@export var coyote_time := 0.2  # How long after leaving ground you can still jump
#boostin
@export_group("Boost")
@export var boost_multiplier := 1.5 # how much faster than base speed
@export var boost_acceleration := 30.0 #how quick it hits boost speed
@export var boost_fov_increase := 10.0 #fov change amount

#wallrunnin
@export_group("Wallrun")
@export var wallrun_speed := 10.0 #when wallrunning
@export var wallrun_dur := 2.0 #how long to wallrun
@export var wallrun_min_speed := 4.0 # how much speed needed to wallrun
@export var wall_grav_multi := 0.2 #low grav when running, gravity markiplier
@export var wall_jump_impulse := 12.0 # how much to jump up from the wall
@export var wall_jump_away_force := 8.0 # how much to push from the wall
@export var wall_detect_distance := 0.6 #how far away do we check walls from


var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.BACK 
var _gravity := -30.0 # how quick we fall


#more forgiving jumps when leaving the platforms, wile e coyote time


var _jump_buffer_timer := 0.0
var _coyote_timer := 0.0

#fov + boost checks
var _is_boosting := false
var _base_fov := 75.0 #base fov


# Wall running tracking
var _wall_run_timer := 0.0
var _wall_normal := Vector3.ZERO # which direction the wall faces
var _wall_side := 0 # -1 = left wall, 1 = right wall, 0 = no wall
var _current_camera_tilt := 0.0


@onready var _camera_pivot: Node3D = %CameraPivot #the node the camera pivots on
@onready var _camera: Camera3D = %Camera3D #the camera itself
@onready var _skin: Node3D = %capsuleGuy # the model/skin


#ray casts for the character
var _wallray_left: RayCast3D
var _wallray_right: RayCast3D

func _ready() -> void:
	_base_fov = _camera.fov
	_wallcast_setup() #run it at the start/ready for wall run rays

func _wallcast_setup() -> void:
	# make left wall detection ray
	_wallray_left = RayCast3D.new()
	add_child(_wallray_left)
	_wallray_left.position = Vector3(0, 0.5, 0) # middle of character height
	_wallray_left.target_position = Vector3(-wall_detect_distance, 0, 0)
	_wallray_left.enabled = true
	
	# make ray, much like the left, but on the right
	_wallray_right = RayCast3D.new()
	add_child(_wallray_right)
	_wallray_right.position = Vector3(0, 0.5, 0)
	_wallray_right.target_position = Vector3(wall_detect_distance, 0, 0)
	_wallray_right.enabled = true

#left click to allow mouse camera, esc to exit it
func  _input(event: InputEvent) -> void:
	if event.is_action_pressed("left_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
func _unhandled_input(event: InputEvent) -> void:
	var is_camera_motion := (
		event is InputEventMouseMotion and
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)
	if is_camera_motion:
		_camera_input_direction = event.screen_relative * mouseSensitivity


func _physics_process(delta: float) -> void:
	
	#the windup? no, the pitch (vertical
	_camera_pivot.rotation.x += + _camera_input_direction.y * delta
	_camera_pivot.rotation.x = clamp(_camera_pivot.rotation.x, -PI / 6.0, PI / 3.0)
	#yaw 
	_camera_pivot.rotation.y -= + _camera_input_direction.x * delta
	
	_camera_input_direction = Vector2.ZERO
	
	#IM HEREEEEEEEEEEEEEE
	
	
	
#	get the input from the button presses and the direction vectors from where the camera is facing
	var raw_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := _camera.global_basis.z
	var right := _camera.global_basis.x
	
#	this is the way forward
	var move_direction := forward * raw_input.y + right * raw_input.x
	move_direction.y = 0.0 #makes it so if we look at ground, it doesn't mess with the direction of movement
	move_direction = move_direction.normalized()
	#	boosting
# button held? 
	_is_boosting = Input.is_action_pressed("boost")
	
	var target_speed := move_speed * boost_multiplier if _is_boosting else move_speed
	var target_accel := boost_acceleration if _is_boosting else acceleration
	
	var target_fov := _base_fov + boost_fov_increase if _is_boosting else _base_fov
	_camera.fov = lerp(_camera.fov, target_fov, 10.0 * delta)
	
	
#	storing velocities
	var y_velocity := velocity.y
	velocity.y = 0.0
	velocity = velocity.move_toward(move_direction * target_speed, target_accel * delta)
	velocity.y = y_velocity + _gravity * delta

		
		# Track time since leaving ground
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta

# Track jump button press
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time

	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta

# Jump if: button pressed recently AND (on ground OR just left ground)
	var can_jump := _jump_buffer_timer > 0.0 and (_coyote_timer > 0.0)
	if can_jump:
		velocity.y = jump_impulse
		_jump_buffer_timer = 0.0  # Use up the buffered jump

	
	
	move_and_slide()
	
	if move_direction.length() > 0.2:
		_last_movement_direction = move_direction
	var target_angle := Vector3.BACK.signed_angle_to(_last_movement_direction, Vector3.UP)
#	turn model/skin with the angle of the movement
# lerp_angle helps keep things smooth, three parameters, where from, where to, how quick
	_skin.global_rotation.y = lerp_angle(_skin.rotation.y, target_angle, rotation_speed * delta)
	
	
