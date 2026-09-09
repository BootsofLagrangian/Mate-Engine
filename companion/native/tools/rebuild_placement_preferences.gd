extends SceneTree
## Offline replay of explicit placement events. No model training/GPU required.
func argument(key:String)->String:
	var args:=OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i]==key:return args[i+1]
	return ""
func _initialize()->void:
	var input:=argument("--input")
	var output:=argument("--output")
	if input.is_empty() or output.is_empty():push_error("--input events.json --output preferences.json required");quit(2);return
	var file:=FileAccess.open(input,FileAccess.READ)
	if file==null or file.get_length()>131072:push_error("invalid input");quit(2);return
	var data=JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("events") is Array:push_error("expected placement event document");quit(2);return
	var learner=load("res://scripts/placement_preferences.gd").new()
	if not learner.configure(output) or not learner.rebuild(data.events):push_error("placement rebuild rejected");quit(2);return
	print(JSON.stringify({"event_count":learner.export_diagnostics().event_count,"output":output,"source":"explicit placements only"}))
	quit()
