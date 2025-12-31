class_name FogOfWarRenderer
extends Node3D

## 視野範囲レンダラー
## プレイヤーの視野範囲を3Dで描画

@export_group("表示設定")
@export var fog_height: float = 0.05  # 視野を描画する高さ（地面付近）
@export var visible_color: Color = Color(1.0, 1.0, 0.5, 0.3)  # 視野内の色（薄い黄色）
@export var cull_margin: float = 50.0  # カリングマージン（視野距離に基づいた適切な値）

# メッシュインスタンス
var visibility_mesh_instance: MeshInstance3D = null

# マテリアル
var visibility_material: StandardMaterial3D = null

# dirtyフラグ（1フレームに1回のみ更新）
var _mesh_dirty: bool = false


func _ready() -> void:
	_setup_visibility_layer()

	# FogOfWarManagerに登録
	var fow = _get_fog_of_war_manager()
	if fow:
		fow.set_fog_renderer(self)
		fow.fog_updated.connect(_on_fog_updated)


func _process(_delta: float) -> void:
	# dirtyフラグが立っている場合のみメッシュを更新（1フレームに1回）
	if _mesh_dirty:
		_mesh_dirty = false
		_update_visibility_mesh()


func _exit_tree() -> void:
	var fow = _get_fog_of_war_manager()
	if fow and fow.fog_updated.is_connected(_on_fog_updated):
		fow.fog_updated.disconnect(_on_fog_updated)


## FogOfWarManagerへの参照を取得
func _get_fog_of_war_manager() -> Node:
	return GameManager.fog_of_war_manager if GameManager else null


## 視野レイヤーをセットアップ（動的視野ポリゴン用）
func _setup_visibility_layer() -> void:
	visibility_mesh_instance = MeshInstance3D.new()
	visibility_mesh_instance.name = "VisibilityMesh"
	visibility_mesh_instance.extra_cull_margin = cull_margin  # 適切なカリングマージン
	add_child(visibility_mesh_instance)

	# マテリアルを作成
	visibility_material = StandardMaterial3D.new()
	visibility_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visibility_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visibility_material.albedo_color = visible_color
	visibility_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## 視野メッシュを更新
func _update_visibility_mesh() -> void:
	var fow = _get_fog_of_war_manager()
	if not fow:
		return

	var visible_points: Array = fow.get_current_visible_points()
	if visible_points.size() < 3:
		visibility_mesh_instance.mesh = null
		return

	# 各視野コンポーネントごとにポリゴンを生成
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var triangle_count := 0
	for component in fow.vision_components:
		if not component or component.visible_points.size() < 3:
			continue

		var points: Array = component.visible_points
		var center: Vector3 = points[0] as Vector3  # 最初のポイントは中心

		# 扇形をトライアングルファンで描画
		for i in range(1, points.size() - 1):
			var p1: Vector3 = points[i] as Vector3
			var p2: Vector3 = points[i + 1] as Vector3

			# 高さを調整（地面から少し上）
			var c := Vector3(center.x, fog_height, center.z)
			var v1 := Vector3(p1.x, fog_height, p1.z)
			var v2 := Vector3(p2.x, fog_height, p2.z)

			st.add_vertex(c)
			st.add_vertex(v1)
			st.add_vertex(v2)
			triangle_count += 1

	if triangle_count > 0:
		# generate_normals()をスキップ - unshadedマテリアルでは不要
		visibility_mesh_instance.mesh = st.commit()
		visibility_mesh_instance.material_override = visibility_material
	else:
		visibility_mesh_instance.mesh = null


## フォグが更新されたときのコールバック
func _on_fog_updated() -> void:
	# dirtyフラグを立てる（_processで1フレームに1回だけ更新）
	_mesh_dirty = true


## マップ設定を更新（互換性のため残す）
func set_map_bounds(_center: Vector3, _size: Vector2) -> void:
	pass
