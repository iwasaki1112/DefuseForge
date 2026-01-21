extends Resource
class_name LightingPreset
## ライティングプリセット定義
## DirectionalLightとEnvironmentの設定を保持

# ============================================
# Basic Info
# ============================================
@export_group("Basic Info")
@export var id: String = ""  ## 一意の識別子
@export var display_name: String = ""  ## UI表示名

# ============================================
# Directional Light
# ============================================
@export_group("Directional Light")
@export var light_energy: float = 0.3  ## 光の強さ
@export var light_color: Color = Color(1.0, 0.98, 0.95, 1.0)  ## 光の色
@export var shadow_enabled: bool = true  ## 影を有効化
@export var shadow_blur: float = 0.7  ## 影のぼかし
@export var shadow_bias: float = 0.1  ## 影のバイアス
@export var light_pitch: float = -77.0  ## 光の傾き（度）
@export var light_yaw: float = -33.0  ## 光の回転（度）

# ============================================
# Environment
# ============================================
@export_group("Environment")
@export var ambient_energy: float = 0.1  ## アンビエント光の強さ
@export var ambient_color: Color = Color(0.6, 0.65, 0.7, 1.0)  ## アンビエント光の色
@export var background_color: Color = Color(0.3, 0.35, 0.4, 1.0)  ## 背景色

# ============================================
# Mobile Optimization
# ============================================
@export_group("Mobile Optimization")
@export var shadow_distance: float = 30.0  ## 影の最大距離
@export var shadow_size: int = 2048  ## 影の解像度
