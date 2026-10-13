extends RefCounted
## Collision layer bits shared by the builders, the player and the debug tools.

const TERRAIN := 1
const BUILDINGS := 2
const BOUNDARY := 4
const PLAYER := 8
const VEGETATION := 16                      # tree trunks and hedges (M5)
const PROPS := 32                           # street furniture, fences and walls (M6)
const VEHICLES := 64                        # drivable cars (scripts/car.gd)
const VEHICLE_INSIDE := 128                 # walkable vehicle hulls (floor, walls, seats, doors): player only
const BREAKABLE := 256                      # also on the thin trees and light props vehicles bend or knock over
const DEBRIS := 512                         # knocked-over props (scripts/breakables.gd): vehicles and the world only
const REMOTE_PLAYER := 1024                 # the other players of a LAN game (scripts/remote_player.gd): vehicles only

const SOLID := TERRAIN | BUILDINGS          # what can be stood on and casts camera collisions
const PICKABLE := SOLID | VEGETATION | PROPS | VEHICLES    # what the debug picker identifies
