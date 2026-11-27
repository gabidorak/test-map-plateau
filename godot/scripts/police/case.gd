extends RefCounted
## A player the police want (police.gd cases, on the host): how much, where they were reported and last seen, since
## when they are not seen. Positions are pipeline x/y (x east, y north).

var peer := 0
var level := 0                              # 1 reported, 2 on the run (up to 5 later)
var scene := Vector2.ZERO                   # where they were reported
var last := Vector2.ZERO                    # where they were last seen...
var vel := Vector2.ZERO                     # ...going at this (m/s)
var since := 0.0                            # s not seen
var seen := false                           # seen by the police now (a car, the helicopter, an officer on foot)
var vehicle := ""                           # carjack key of the car they stole


func _init(p: int, at: Vector2, key: String) -> void:
	peer = p
	scene = at
	last = at
	vehicle = key
