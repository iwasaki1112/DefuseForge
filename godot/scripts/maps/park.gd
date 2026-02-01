extends MapBase
## Park map initialization script
## Sets wall/obstacle collision layers for vision system and path blocking

func _ready() -> void:
	_map_name = "PARK"
	super._ready()
