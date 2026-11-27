extends RefCounted
## A toy figure on foot, of primitive meshes (the bots' drivers pulled out of their cars: scripts/carjack/ejected_driver.gd;
## the police's officers: scripts/police/foot/officer.gd): front +Z, feet on y = 0, 1.8 m tall; trousers, a jacket over a
## shirt, a cap. build() makes it under a node and returns its joints, which walk() swings.

const Kit = preload("res://scripts/build_kit.gd")

const SKIN := Color(0.93, 0.74, 0.6)


## The figure under `parent` in `jacket` (the arms and the cap too), `trousers`, `shirt` (the collar), the cap's peak in
## `peak`: {"body" (its root, the whole figure), "legs" [left, right] (hips), "arms" [left, right] (shoulders)}.
static func build(parent: Node3D, jacket: Color, trousers: Color, shirt: Color, peak: Color) -> Dictionary:
	var uniform := Kit.plain(jacket, 0.5)
	var legs_mat := Kit.plain(trousers, 0.5)
	var peak_mat := Kit.plain(peak, 0.5)
	var skin := Kit.plain(SKIN, 0.55)
	var shoe := Kit.plain(Color(0.03, 0.03, 0.03), 0.2)
	var collar := Kit.plain(shirt, 0.5)
	var body := Node3D.new()
	parent.add_child(body)
	var legs: Array[Node3D] = []
	var arms: Array[Node3D] = []
	for side: float in [1.0, -1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.1, 0.93, 0.0)
		body.add_child(hip)
		part(hip, cylinder(0.075, 0.09, 0.84), legs_mat, Vector3(0.0, -0.44, 0.0))
		part(hip, box(Vector3(0.11, 0.07, 0.26)), shoe, Vector3(0.0, -0.88, 0.05))
		legs.append(hip)
	part(body, cylinder(0.23, 0.2, 0.62), uniform, Vector3(0.0, 1.25, 0.0), Vector3(1.0, 1.0, 0.62))
	part(body, box(Vector3(0.11, 0.22, 0.02)), collar, Vector3(0.0, 1.46, 0.135))
	for side: float in [1.0, -1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.26, 1.53, 0.0)
		body.add_child(shoulder)
		part(shoulder, capsule(0.06, 0.62), uniform, Vector3(0.0, -0.28, 0.0))
		part(shoulder, sphere(0.055), skin, Vector3(0.0, -0.62, 0.0))
		arms.append(shoulder)
	part(body, capsule(0.055, 0.15), skin, Vector3(0.0, 1.64, 0.0))
	part(body, sphere(0.135), skin, Vector3(0.0, 1.77, 0.0), Vector3(1.0, 1.08, 1.0))
	part(body, cylinder(0.14, 0.145, 0.07), uniform, Vector3(0.0, 1.88, 0.0))      # the cap
	part(body, box(Vector3(0.2, 0.02, 0.1)), peak_mat, Vector3(0.0, 1.85, 0.15))   # its peak
	return {"body": body, "legs": legs, "arms": arms}


## Swings the legs (and the arms, unless `arms_free`) of figure `fig` going at `speed` m/s; `phase` its stride's,
## advanced and returned. The body bobs a little.
static func walk(fig: Dictionary, phase: float, speed: float, delta: float, arms_free := false) -> float:
	var swing := clampf(speed / 2.0, 0.0, 1.6)
	phase += delta * (2.0 + 4.0 * swing) if swing > 0.0 else 0.0
	var s := sin(phase) * 0.55 * minf(swing, 1.0)
	fig["legs"][0].rotation.x = s
	fig["legs"][1].rotation.x = -s
	if not arms_free:
		var k := minf(8.0 * delta, 1.0)
		fig["arms"][0].rotation.x = lerpf(fig["arms"][0].rotation.x, -s * 0.8, k)
		fig["arms"][1].rotation.x = lerpf(fig["arms"][1].rotation.x, s * 0.8, k)
	fig["body"].position.y = absf(cos(phase)) * 0.05 * minf(swing, 1.0)
	return phase


static func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale_ := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale_
	parent.add_child(mi)
	return mi


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 3
	return c


static func sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func cylinder(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
