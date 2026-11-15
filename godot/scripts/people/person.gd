extends RefCounted
## What makes a node a person for scripts/people/people.gd (stunned, carried; the police to come): it is in the group
## GROUP and has
##   person_id: String          "p:<peer>" for a player, "n:<n>" for a bot: the same on every peer
##   person_up() -> bool        standing on the map, shown: a shot may stun them (not in a vehicle, lying, carried...)
##   person_body() -> Node3D    its body, feet at its origin, standing along its Y: what lies down, is carried, and
##                              wears the effects (people_fx.gd)
##   person_name() -> String
##   person_carried() -> bool
##   set_down(on: bool)         lying on the ground (the player: unable to move too), or up again
##   carry_on(body: Node3D)     lying over the shoulders of `body` (another person's body) as CARRY_POSE, following it;
##                              null: put down
##   put_at(pos: Vector3)       standing (or lying) at `pos`, put down there
## Its feet are its global_position. The player (player.gd), the other players (remote_player.gd) and the bots on foot
## (scripts/carjack/ejected_driver.gd) are persons. No dependency here: those scripts load it.

const GROUP := "people"
## A body carried, in its carrier's body's frame: lying across the shoulders, face down, the head on the carrier's right.
const CARRY_POSE := Transform3D(Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP), Vector3(-0.85, 1.5, 0.08))
