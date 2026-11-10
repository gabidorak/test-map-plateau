extends Node
## What PTA Online's jobs share (bus_job.gd, fire_job.gd, tow_job.gd, made by online_mode.gd): their mode, who is on
## duty, the host's answers to a duty request and going off duty (a job says how a duty ends: end_duty()).

signal answered(ok: bool, text: String)     # the host's answer to our last duty request

var mode: Node                              # online_mode.gd, which makes the job
var duties := {}                            # host: peer -> its duty


## Host: the duty of `peer` over, `why` told to it (each job ends its own duties).
func end_duty(_peer: int, _why: String, _tell := true) -> void:
	pass


@rpc("any_peer", "call_remote", "reliable")
func _h_off() -> void:
	if not mode.hosting:
		return
	var peer: int = mode._sender()
	if duties.has(peer):
		end_duty(peer, "you asked")
		mode.send_to(peer, self, "_c_answer", [true, "Off duty."])
	else:
		mode.send_to(peer, self, "_c_answer", [false, "You aren't on duty."])


@rpc("authority", "call_remote", "reliable")
func _c_answer(ok: bool, text: String) -> void:
	answered.emit(ok, text)
	if ok and mode.ui_open():
		mode.close_ui()
	if ok or not mode.ui_open():
		mode.game.toast(text)
	else:
		mode._panel.set_status(text)
