extends MapBase
## Office map initialization script
## Sets wall/door/ground collision layers for vision system and path blocking

func _ready() -> void:
	_map_name = "OFFICE"
	super._ready()
