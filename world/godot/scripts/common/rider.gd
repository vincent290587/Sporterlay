class_name Rider
extends Node3D
## First-person rider. This world's own bike physics turn power into speed along the
## route: climbs slow you down on screen, but nothing reaches the trainer.

const GRAVITY := 9.81
const WHEEL_INERTIA_KG := 1.0     # both wheels' rotational inertia, as extra mass
const MIN_DRIVE_SPEED := 1.0      # m/s; caps the push force P / v when starting off
const MAX_SPEED := 30.0
const STEP := 1.0 / 120.0

var total_mass_kg := 85.0         # rider + bike
var cda := 0.32                   # on the hoods; ~0.25 in the drops
var crr := 0.004
var air_density := 1.225
var drivetrain_efficiency := 0.976
var eye_height := 1.55
var lane_offset := 1.0            # keep right
var look_ahead := 14.0

var route: Route
var speed := 0.0
var distance := 0.0
var odometer := 0.0
var grade := 0.0
var camera := Camera3D.new()
var _placed := false


func _ready() -> void:
	camera.fov = 72.0
	camera.near = 0.1
	camera.far = 12000.0
	add_child(camera)
	camera.make_current()


## Forget the camera's smoothing, for a jump to another road.
func reset() -> void:
	_placed = false
	grade = 0.0


func _integrate(watts: float, dt: float) -> void:
	# m dv/dt = P/v - m g (sin a + Crr cos a) - 1/2 rho CdA v^2
	var a := atan(grade / 100.0)
	var drive := watts * drivetrain_efficiency / maxf(speed, MIN_DRIVE_SPEED)
	var resist := total_mass_kg * GRAVITY * (sin(a) + crr * cos(a)) + 0.5 * air_density * cda * speed * speed
	speed = clampf(speed + (drive - resist) / (total_mass_kg + WHEEL_INERTIA_KG) * dt, 0.0, MAX_SPEED)
	# rolling resistance can't push you backwards
	if speed < 0.05 and watts <= 0.0 and grade >= 0.0:
		speed = 0.0


func advance(watts: float, dt: float) -> void:
	# grade follows the road with ~1 s lag, so a kink isn't a jolt
	grade = lerpf(grade, clampf(route.grade_at(distance), -25.0, 25.0), 1.0 - exp(-dt))
	var left := minf(dt, 0.25)
	while left > 0.0:
		var h := minf(left, STEP)
		_integrate(watts, h)
		distance += speed * h
		odometer += speed * h
		left -= h
	distance = fposmod(distance, route.length)
	_place(dt)


func _place(dt: float) -> void:
	var ground := route.position_at(distance) + route.right_at(distance) * lane_offset
	var ahead_s := distance + look_ahead
	var ahead := route.position_at(ahead_s) + route.right_at(ahead_s) * lane_offset
	var eye := ground + Vector3.UP * eye_height
	var target := Transform3D(Basis(), eye).looking_at(ahead + Vector3.UP * eye_height * 0.7, Vector3.UP)
	var q := target.basis.get_rotation_quaternion()
	if _placed:
		q = basis.get_rotation_quaternion().slerp(q, 1.0 - exp(-4.0 * dt))
	transform = Transform3D(Basis(q), eye)
	_placed = true
