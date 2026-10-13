extends VehicleBody3D
## Rear section of an articulated vehicle (the 18 m bus). scripts/car.gd builds it from the model's layout ("trailer")
## with its own wheels, body box, walkable hull and doors, and hinges it to the front section with a joint at the hitch;
## the front section drives it (engine, brakes). Its frame is the front section's while the vehicle is straight.
## Like car.gd, the player standing in it is carried by it (game.gd, player.set_carrier).

var head: VehicleBody3D                     # the front section (car.gd)
var interior := AABB()                      # walkable volume in this section's frame
var inside: StaticBody3D                    # walkable hull
var door_centres: Array[Vector3] = []       # this section's frame, doorway centre on the floor


## True when `p` (global) is inside the walkable interior.
func carries(p: Vector3, margin := 0.0) -> bool:
	return interior.size != Vector3.ZERO and interior.grow(margin).has_point(to_local(p))


## Velocity of the section at global point `p`.
func velocity_at(p: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - global_transform * center_of_mass)
