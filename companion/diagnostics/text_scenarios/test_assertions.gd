extends "../../native/tools/run_text_scenario.gd"

func run() -> void:
	var failures := 0
	var cases: Array = [
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
