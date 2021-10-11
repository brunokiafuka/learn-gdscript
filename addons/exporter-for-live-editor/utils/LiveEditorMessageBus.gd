# Singleton that takes care of receiving messages from running scripts and then
# re-dispatches them to anyone listening.
#
# Requires running scripts to have been transformed so that `print`,
# `push_error`, `push_warning`, and such call the singleton.
#
# A provided convenience function can do this for any provided script text.
#
# NOTE: `assert` statements expect the `assert(condition, message)` form.
# `assert(condition)` will not work.
extends Node

const RegExp := preload("./RegExp.gd")

enum MESSAGE_TYPE { PRINT, PRINTS, ERROR, WARNING, ASSERT }

signal print_request(type, thing_to_print, file_name, line_nb, character)

var script_replacements := RegExp.collection(
	{
		"\\b(?<command>prints)\\((?<args>.*?)\\)":
		"LiveEditorMessageBus.print_log([{args}], \"{file}\", {line}, {char})",
		"\\b(?<command>print)\\((?<args>.*?)\\)":
		"LiveEditorMessageBus.print_log([{args}], \"{file}\", {line}, {char})",
		"\\b(?<command>push_error)\\((?<args>.*?)\\)":
		"LiveEditorMessageBus.print_error({args}, \"{file}\", {line}, {char})",
		"\\b(?<command>push_warning)\\((?<args>.*?)\\)":
		"LiveEditorMessageBus.print_warning({args}, \"{file}\", {line}, {char})",
		"\\b(?<command>assert)\\((?<args>.*?)\\)":
		"LiveEditorMessageBus.print_assert({args}, \"{file}\", {line}, {char})",
	}
)

# If `true`, calls to this singleton will also print to the regular Godot
# console. We set this to true by default on debug builds, and false by default
# everywhere else.
export var print_to_output: bool = OS.is_debug_build()


# Transforms a script's print statements (and similar) to calls to this
# singleton.
func replace_script(script_file_name: String, script_text: String) -> String:
	var lines = script_text.split("\n")
	for line_nb in lines.size():
		var line: String = lines[line_nb]
		for _regex in script_replacements._regexes:
			var regex := _regex as RegEx
			var replacement: String = script_replacements._regexes[regex]
			var start := 0
			var end := line.length()
			while start < end:
				var maybe_match = regex.search(line, start)
				if not maybe_match:
					start = end
					break
				else:
					var m := maybe_match as RegExMatch
					var starting_char := m.get_start()
					var ending_char := m.get_end()
					var args = m.get_string("args")
					if args[0] == '"':
						# Godot somehow removes `"` if they are the first
						# character of a string
						args = " " + args
					var command = m.get_string("command")
					var config = {
						"command": command,
						"args": args,
						"line": line_nb,
						"file": script_file_name,
						"char": starting_char,
					}
					var slice_middle := replacement.format(config)
					var slice_beginning := line.left(starting_char)
					var slice_end := line.right(ending_char)
					var replaced_line := slice_beginning + slice_middle + slice_end
					var diff: int = abs(replaced_line.length() - line.length())
					start = ending_char + diff
					lines[line_nb] = replaced_line
	return lines.join("\n")


func print_log(thing_to_print: Array, file_name: String, line_nb: int = 0, character: int = 0) -> void:
	var line = PoolStringArray(thing_to_print).join(" ")
	print_request(MESSAGE_TYPE.PRINT, line, file_name, line_nb, character)
	if print_to_output:
		prints(thing_to_print)


func print_error(thing_to_print, file_name: String, line_nb: int = 0, character: int = 0) -> void:
	print_request(MESSAGE_TYPE.ERROR, String(thing_to_print), file_name, line_nb, character)
	if print_to_output:
		push_error(thing_to_print)


func print_warning(thing_to_print, file_name: String, line_nb: int = 0, character: int = 0) -> void:
	print_request(MESSAGE_TYPE.WARNING, String(thing_to_print), file_name, line_nb, character)
	if print_to_output:
		push_warning(thing_to_print)


func print_assert(
	assertion: bool, provided_message := "", file_name := "", line_nb: int = 0, character: int = 0
) -> void:
	var message = ""
	if not assertion:
		message = provided_message if provided_message != "" else "Assertion failed"

	if not assertion:
		print_request(MESSAGE_TYPE.ASSERT, message, file_name, line_nb, character)
	if print_to_output:
		push_error(message)


# This is a proxy for emitting the signal, to work around Godot's lack of signal
# typing.
func print_request(
	message_type: int, message: String, file_name: String, line_nb: int, character: int
) -> void:
	emit_signal("print_request", message_type, message, file_name, line_nb, character)