extends Node
## Music, ambience and sound effects, on the buses from default_bus_layout.tres (volumes come
## from Settings). Registered as the `Audio` autoload, so music keeps playing across scenes.
##
## Sounds are found by name, like art:
##   play_music("title")        -> res://assets/audio/music/mus_title.ogg
##   play_ambience("night")     -> res://assets/audio/ambience/amb_night.ogg
##   play_sfx("lock_open")      -> res://assets/audio/sfx/sfx_lock_open.ogg
## .ogg, .mp3 and .wav are tried in that order. A missing file logs one warning and plays nothing,
## so scripts can name sounds before they exist.

const MUSIC_PATH := "res://assets/audio/music/mus_%s"
const AMBIENCE_PATH := "res://assets/audio/ambience/amb_%s"
const SFX_PATH := "res://assets/audio/sfx/sfx_%s"
const EXTENSIONS: Array[String] = ["ogg", "mp3", "wav"]
const MUSIC_FADE := 1.5
const AMBIENCE_FADE := 2.0
## How many sound effects can play at once.
const SFX_VOICES := 8

## Name of the music or ambience playing (or fading in), "" when none.
var current_music: String = ""
var current_ambience: String = ""

var _music: AudioChannel
var _ambience: AudioChannel
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx: int = 0
var _warned: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioChannel.new(self, &"Music")
	_ambience = AudioChannel.new(self, &"Ambience")
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)


## Crossfades to `track`. Asking for the track that's already playing does nothing.
func play_music(track: String, fade: float = MUSIC_FADE) -> void:
	if track == current_music:
		return
	current_music = track
	_music.play(find_stream(MUSIC_PATH, track, true), fade)


func stop_music(fade: float = MUSIC_FADE) -> void:
	current_music = ""
	_music.play(null, fade)


func play_ambience(loop_name: String, fade: float = AMBIENCE_FADE) -> void:
	if loop_name == current_ambience:
		return
	current_ambience = loop_name
	_ambience.play(find_stream(AMBIENCE_PATH, loop_name, true), fade)


func stop_ambience(fade: float = AMBIENCE_FADE) -> void:
	current_ambience = ""
	_ambience.play(null, fade)


## Plays a one-shot sound effect. Returns false when the file is missing.
func play_sfx(sound: String, volume_db: float = 0.0) -> bool:
	var stream := find_stream(SFX_PATH, sound, false)
	if stream == null:
		return false
	var player := _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()
	return true


## Stops everything at once and lets go of the loaded streams.
func stop_all() -> void:
	stop_music(0.0)
	stop_ambience(0.0)
	for player: AudioStreamPlayer in get_children():
		player.stop()
		player.stream = null


## Loads `<pattern % sound_name>.<ext>` for the first extension that exists, or null.
## `loop` turns looping on for music and ambience.
func find_stream(pattern: String, sound_name: String, loop: bool) -> AudioStream:
	if sound_name.is_empty():
		return null
	for ext in EXTENSIONS:
		var path := "%s.%s" % [pattern % sound_name, ext]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if loop:
				_set_loop(stream)
			return stream
	var missing := pattern % sound_name
	if not _warned.has(missing):
		_warned[missing] = true
		push_warning("Audio: no file for %s (.ogg/.mp3/.wav)" % missing)
	return null


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)


## Two players on one bus, so a new stream can fade in while the old one fades out.
class AudioChannel extends RefCounted:
	var _players: Array[AudioStreamPlayer] = []
	var _active: int = 0
	var _owner: Node

	func _init(owner: Node, bus: StringName) -> void:
		_owner = owner
		for i in 2:
			var player := AudioStreamPlayer.new()
			player.bus = bus
			player.volume_db = linear_to_db(0.0001)
			owner.add_child(player)
			_players.append(player)

	## Fades the current stream out and `stream` in (null just fades out).
	func play(stream: AudioStream, fade: float) -> void:
		var old := _players[_active]
		_fade(old, 0.0, fade, true)
		if stream == null:
			return
		_active = 1 - _active
		var incoming := _players[_active]
		incoming.stream = stream
		incoming.volume_db = linear_to_db(0.0001)
		incoming.play()
		_fade(incoming, 1.0, fade, false)

	func _fade(player: AudioStreamPlayer, to: float, seconds: float, stop_after: bool) -> void:
		if player.has_meta(&"tween"):
			var running := player.get_meta(&"tween") as Tween
			if running and running.is_valid():
				running.kill()
		if seconds <= 0.0:
			player.volume_db = linear_to_db(maxf(to, 0.0001))
			if stop_after:
				player.stop()
			return
		var from := db_to_linear(player.volume_db)
		var tween := _owner.create_tween()
		tween.tween_method(func(v: float) -> void: player.volume_db = linear_to_db(maxf(v, 0.0001)), from, to, seconds)
		if stop_after:
			tween.tween_callback(player.stop)
		player.set_meta(&"tween", tween)
