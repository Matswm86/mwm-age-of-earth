class_name FogOfWar
extends RefCounted

## Fog of war on the 128 x 128 nav grid, one byte per 4 m cell: 0 unexplored, 128 explored,
## 255 visible. update() runs SpikeConfig.FOG_HZ times a second: cells lit last time drop to
## explored, then every distinct cell that holds a player unit stamps a sight disc. The bytes go
## to a 128 x 128 R8 texture that the terrain and lake shaders sample with linear filtering.

var texture: ImageTexture
var bytes := PackedByteArray()
var update_ms: float = 0.0

var _img: Image
var _offsets := PackedInt32Array()
var _lit := PackedInt32Array()
var _src := PackedByteArray()
var _src_list := PackedInt32Array()


func _init() -> void:
	var n: int = SpikeConfig.NAV_CELLS
	bytes.resize(n * n)
	bytes.fill(0)
	_src.resize(n * n)
	_src.fill(0)
	var r: int = int(ceilf(SpikeConfig.UNIT_SIGHT_M / SpikeConfig.NAV_CELL_M))
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			if di * di + dj * dj <= r * r:
				_offsets.append(di)
				_offsets.append(dj)
	_img = Image.create_from_data(n, n, false, Image.FORMAT_R8, bytes)
	texture = ImageTexture.create_from_image(_img)


func reset() -> void:
	bytes.fill(0)
	_lit.resize(0)


## Fog off (button): every cell visible, uploaded once.
func set_all_visible() -> void:
	bytes.fill(255)
	_lit.resize(0)
	var n: int = SpikeConfig.NAV_CELLS
	_img.set_data(n, n, false, Image.FORMAT_R8, bytes)
	texture.update(_img)


func is_visible_cell(cell: int) -> bool:
	return bytes[cell] == 255


## Stamps sight around every player unit (team 0) and every cell in `extra` (player buildings),
## then uploads the texture.
func update(
	cells: PackedInt32Array, teams: PackedInt32Array, count: int, extra := PackedInt32Array()
) -> void:
	var t0: int = Time.get_ticks_usec()
	var n: int = SpikeConfig.NAV_CELLS
	for c in _lit:
		bytes[c] = 128
	_lit.resize(0)
	_src_list.resize(0)
	for i in count:
		if teams[i] != 0:
			continue
		var c: int = cells[i]
		if _src[c] == 0:
			_src[c] = 1
			_src_list.append(c)
	for c in extra:
		if _src[c] == 0:
			_src[c] = 1
			_src_list.append(c)
	var off_n: int = _offsets.size()
	for c in _src_list:
		_src[c] = 0
		var ci: int = c & (n - 1)
		var cj: int = c >> SpikeConfig.NAV_SHIFT
		var k: int = 0
		while k < off_n:
			var i: int = ci + _offsets[k]
			var j: int = cj + _offsets[k + 1]
			k += 2
			if i < 0 or j < 0 or i >= n or j >= n:
				continue
			var cell: int = j * n + i
			if bytes[cell] != 255:
				bytes[cell] = 255
				_lit.append(cell)
	_img.set_data(n, n, false, Image.FORMAT_R8, bytes)
	texture.update(_img)
	update_ms = (Time.get_ticks_usec() - t0) / 1000.0
