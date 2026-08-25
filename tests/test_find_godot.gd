extends RefCounted

func run() -> bool:
	if OS.get_name() != "Windows":
		return true
	return test_program_files_fallback_has_one_clean_terminal_result()

func test_program_files_fallback_has_one_clean_terminal_result() -> bool:
	var fixture_root := ProjectSettings.globalize_path(
		"user://find_godot_fallback_%s" % Time.get_ticks_usec()
	)
	var tools_dir := fixture_root.path_join("tools")
	var script_path := tools_dir.path_join("find_godot.ps1")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(tools_dir)
	if not _expect(mkdir_error == OK, "The find_godot fallback fixture directory must be created."):
		_cleanup_fixture(script_path, tools_dir, fixture_root)
		return false

	var source_path := ProjectSettings.globalize_path("res://tools/find_godot.ps1")
	var copy_error := DirAccess.copy_absolute(source_path, script_path)
	if not _expect(copy_error == OK, "The real find_godot script must be copied into the isolated fixture."):
		_cleanup_fixture(script_path, tools_dir, fixture_root)
		return false

	var escaped_script_path := script_path.replace("'", "''")
	var command := "$env:GODOT_BIN = $null; & '%s'" % escaped_script_path
	var output: Array = []
	var exit_code := OS.execute(
		"powershell.exe",
		PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command]),
		output,
		true
	)
	var combined_output := ""
	for line in output:
		combined_output += str(line)

	var has_binding_error := (
		combined_output.contains("ParameterBindingException")
		or combined_output.contains("Cannot bind parameter")
		or combined_output.contains("Nao e possivel associar o parametro")
		or combined_output.contains("Não é possível associar o parâmetro")
	)
	var has_valid_terminal_result := false
	if exit_code == 0:
		has_valid_terminal_result = FileAccess.file_exists(combined_output.strip_edges())
	else:
		has_valid_terminal_result = combined_output.contains(
			"Godot console executable not found. Set GODOT_BIN or install the portable runtime"
		)

	var passed := (
		_expect(not has_binding_error, "The Program Files fallback must not emit a PowerShell parameter-binding error. Output: %s" % combined_output)
		and _expect(has_valid_terminal_result, "The isolated locator must return an existing executable or only its intentional not-found error. Exit %s, output: %s" % [exit_code, combined_output])
	)
	_cleanup_fixture(script_path, tools_dir, fixture_root)
	return passed

func _cleanup_fixture(script_path: String, tools_dir: String, fixture_root: String) -> void:
	if FileAccess.file_exists(script_path):
		DirAccess.remove_absolute(script_path)
	if DirAccess.dir_exists_absolute(tools_dir):
		DirAccess.remove_absolute(tools_dir)
	if DirAccess.dir_exists_absolute(fixture_root):
		DirAccess.remove_absolute(fixture_root)

func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition
