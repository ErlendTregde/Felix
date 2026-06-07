extends SkeletonModifier3D
class_name HeadHideModifier
## Collapses the head bone to a near-zero scale so the local player never sees their
## own head in the seated/first-person view. Runs after the AnimationPlayer each frame
## (so the animation can't restore the scale). Only added to the LOCAL player's body.

var head_bone: int = -1

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk and head_bone >= 0:
		sk.set_bone_pose_scale(head_bone, Vector3(0.001, 0.001, 0.001))
