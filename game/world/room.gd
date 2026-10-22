class_name Room
extends Node2D
## A built room: tiles, collision, shadows, props and lights for one .room file.

var data: RoomData
var theme: Dictionary
var rect: Rect2                 # world-space rectangle
var player_start := Vector2.ZERO      # world space
var hearths: Array[Vector2] = []      # world space
var seals: Dictionary = {}            # entity id -> {"song", "at" (world), "nodes"}
