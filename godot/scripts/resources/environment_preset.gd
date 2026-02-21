extends Resource
class_name EnvironmentPreset
## 環境プリセット定義
## ライティング・影・レンダリング設定を統合管理

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
@export var light_pitch: float = -77.0  ## 光の傾き（度）
@export var light_yaw: float = -33.0  ## 光の回転（度）

# ============================================
# Shadow
# ============================================
@export_group("Shadow")
@export var shadow_enabled: bool = true  ## 影を有効化
@export var shadow_blur: float = 0.7  ## 影のぼかし
@export var shadow_bias: float = 0.1  ## 影のバイアス
@export var shadow_distance: float = 30.0  ## 影の最大距離
@export_enum("512", "1024", "2048", "4096") var shadow_size: int = 2  ## 影の解像度（0=512, 1=1024, 2=2048, 3=4096）

# ============================================
# Ambient Light
# ============================================
@export_group("Ambient Light")
@export var ambient_energy: float = 0.1  ## アンビエント光の強さ
@export var ambient_color: Color = Color(0.6, 0.65, 0.7, 1.0)  ## アンビエント光の色
@export var background_color: Color = Color(0.3, 0.35, 0.4, 1.0)  ## 背景色

# ============================================
# Rendering Quality
# ============================================
@export_group("Rendering Quality")
@export_range(0.5, 1.0, 0.05) var resolution_scale: float = 0.75  ## 内部解像度スケール
@export var use_fsr: bool = true  ## FSRアップスケーリング

# ============================================
# Post-processing (Mobile Optimization)
# ============================================
@export_group("Post-processing")
@export var ssao_enabled: bool = false  ## SSAO
@export var ssil_enabled: bool = false  ## SSIL
@export var sdfgi_enabled: bool = false  ## SDFGI
@export var glow_enabled: bool = false  ## Glow
@export var glow_intensity: float = 0.4  ## Glowの強さ
@export var glow_bloom: float = 0.1  ## Bloom量
@export var glow_blend_mode: int = 2  ## ブレンドモード (0=Additive, 1=Screen, 2=Softlight, 3=Replace)
@export var glow_hdr_threshold: float = 1.2  ## HDR閾値

@export var fog_enabled: bool = false  ## Fog
@export var fog_light_color: Color = Color(0.75, 0.78, 0.82, 1.0)  ## フォグの色
@export var fog_density: float = 0.002  ## フォグの密度
@export var fog_aerial_perspective: float = 0.0  ## 空気遠近法

@export var adjustment_enabled: bool = false  ## カラー調整
@export var adjustment_brightness: float = 1.0  ## 明るさ
@export var adjustment_contrast: float = 1.05  ## コントラスト
@export var adjustment_saturation: float = 0.95  ## 彩度


## 影の解像度を数値で取得
func get_shadow_size_value() -> int:
	match shadow_size:
		0: return 512
		1: return 1024
		2: return 2048
		3: return 4096
		_: return 2048
