extends Node

## プレイヤーチーム管理
## 操作可能チームを1箇所で設定し、全体に反映する

var player_team: CharacterBase.Team = CharacterBase.Team.TERRORIST


## 指定チームがプレイヤーチームかどうか
func is_player_team(team: CharacterBase.Team) -> bool:
	return team == player_team


## 指定チームが敵チームかどうか
func is_enemy_team(team: CharacterBase.Team) -> bool:
	return team != CharacterBase.Team.NONE and team != player_team
