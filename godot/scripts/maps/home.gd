extends MapBase
## Home map initialization script
## Sets wall/door/ground collision layers for vision system and path blocking

func _ready() -> void:
	_map_name = "HOME"
	super._ready()
