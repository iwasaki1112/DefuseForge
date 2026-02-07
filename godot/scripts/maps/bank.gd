extends MapBase
## Bank map initialization script
## Sets wall/door collision layers for vision system and path blocking

func _ready() -> void:
	_map_name = "BANK"
	super._ready()
