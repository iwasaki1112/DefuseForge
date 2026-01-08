class_name CharacterModel
extends Node3D

## キャラクターモデルノード
## シーンツリーに追加されると自動的にマテリアル設定（明るさ補正）が適用される
## 使い方: GLBモデルの親ノードとしてこのスクリプトをアタッチ

## キャラクター識別名（テクスチャマッチング用、空でもOK）
@export var character_id: String = ""


func _ready() -> void:
	# 自身と全ての子ノードにマテリアル設定を適用
	CharacterSetup.setup_materials(self, character_id)
