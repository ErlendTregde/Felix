extends SkeletonModifier3D
class_name HeadLookModifier
## Layers a yaw/pitch head turn on top of the current animated head pose.
## A SkeletonModifier3D runs AFTER the AnimationPlayer each frame, so we can read
## the animated pose and add the look rotation without it being overwritten.

var head_bone: int = -1
var target_yaw: float = 0.0    # radians — set by BodyRig.set_head_look()
var target_pitch: float = 0.0  # radians

# Flip these if the head turns the wrong way once you see it in-game.
const YAW_SIGN: float = 1.0
const PITCH_SIGN: float = -1.0
# Clamp so the head can never spin into a broken pose.
const MAX_YAW: float = 1.2    # ~69°
const MAX_PITCH: float = 0.7  # ~40°
# Smoothing toward the target so network jitter doesn't make the head snap.
const SMOOTH: float = 0.25

var _cur_yaw: float = 0.0
var _cur_pitch: float = 0.0

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or head_bone < 0:
		return

	_cur_yaw = lerpf(_cur_yaw, clampf(target_yaw, -MAX_YAW, MAX_YAW), SMOOTH)
	_cur_pitch = lerpf(_cur_pitch, clampf(target_pitch, -MAX_PITCH, MAX_PITCH), SMOOTH)

	# Express world up/right in the head's PARENT-local space, so the rotation
	# stays correct regardless of how the spine/neck is oriented by the animation.
	var up_axis := Vector3.UP
	var right_axis := Vector3.RIGHT
	var parent := sk.get_bone_parent(head_bone)
	if parent >= 0:
		var inv := sk.get_bone_global_pose(parent).basis.orthonormalized().inverse()
		up_axis = (inv * Vector3.UP).normalized()
		right_axis = (inv * Vector3.RIGHT).normalized()

	var delta := Quaternion(up_axis, _cur_yaw * YAW_SIGN) * Quaternion(right_axis, _cur_pitch * PITCH_SIGN)
	var cur := sk.get_bone_pose_rotation(head_bone)
	sk.set_bone_pose_rotation(head_bone, delta * cur)
