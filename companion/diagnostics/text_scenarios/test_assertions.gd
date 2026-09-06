extends "../../native/tools/run_text_scenario.gd"

func run() -> void:
	var failures := 0
	var raw := {"fit":{"error":INF},"rows":[{"scale":0.8}]}
	var safe: Dictionary = bounded_diagnostic(raw)
	raw.rows[0].scale = 1.2
	var many: Array = []
	many.resize(40)
	var cases: Array = [
		JSON.parse_string(JSON.stringify(safe)) is Dictionary,
		safe.rows[0].scale == 0.8,
		bounded_diagnostic(many).size() == 33,
		bounded_diagnostic("x".repeat(3000)).length() == 2048,
		native_diagnostic_snapshot() == {"available":false},
		valid_step({"text":"Discuss it","expect_no_intent":true}),
		not valid_step({"text":"Discuss it","expect_no_intent":1}),
		not valid_step({"text":"Discuss it","expect_no_intent":true,"expect_intent":{"kind":"furniture"}}),
		not valid_step({"text":"Discuss it","timeout_s":true}),
		not valid_step({"text":"Discuss it","timeout_s":NAN}),
		not valid_step({"text":"Discuss it","expected_outcomes":["imagined"]}),
		not valid_step({"text":"Discuss it","intent":{"kind":"furniture"}}),
		no_intent_assertion_passes({"expect_no_intent":true},{"type":"action"},{"type":"done"}),
		not no_intent_assertion_passes({"expect_no_intent":true},{"intent":{"kind":"furniture"}},{}),
		not no_intent_assertion_passes({"expect_no_intent":true},{},{"intent":{"kind":"furniture"}}),
	]
	for passed in cases:
		if not passed: failures+=1
	print("TEXT_SCENARIO_ASSERTIONS ",cases.size()-failures," passed ",failures," failed")
	quit(0 if failures==0 else 1)
