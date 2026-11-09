#!/bin/sh
# PTA Online test (offline): opens the game straight into PTA Online played solo, without the server or a login
# (game.gd online_test, online_mode.gd testing): 10 M € (refill in the in-game menu, Esc), every unarmed vehicle in the
# garage, the fly camera, the in-game menu's shortcuts to the bus depot, the fire station and Prestige Motors.
# GODOT: the Godot binary (default: godot on the PATH). Extra arguments go to the game (--name=Tester...).
# PLATEAU_ONLINE_VEHICLES (models, comma-separated) and PLATEAU_ONLINE_MONEY replace the garage and the money.
# From the editor: run the game (F5), PTA Online, "Test offline".
cd "$(dirname "$0")/.." || exit 1
exec "${GODOT:-godot}" --path . -- --online-test "$@"
