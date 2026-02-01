extends MapBase
## Convenience Store map initialization script
## Sets wall/door collision layers for vision system and path blocking

func _ready() -> void:
	_map_name = "CONVENIENCE_STORE"
	super._ready()
