extends Node

## Quick test script for Ollama API connection with gemma3 model.
## Attach this to any Node and run the scene to test.

const OLLAMA_URL := "http://127.0.0.1:11434/api/generate"
const MODEL := "gemma3:1b"

var http_request: HTTPRequest

func _ready() -> void:
	# Create HTTP request node
	http_request = HTTPRequest.new()
	http_request.timeout = 7.0 # Cancel request after no response
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Send a simple test prompt
	send_prompt("Hello! Write a sentence about you.")

func send_prompt(prompt: String) -> void:
	var body := {
		"model": MODEL,
		"prompt": prompt,
		"stream": false # Set to false to get single response
	}
	
	var json_body := JSON.stringify(body)
	var headers := ["Content-Type: application/json"]
	
	print("Sending request to Ollama...")
	print("Prompt: ", prompt)
	
	var error := http_request.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		print("ERROR: Failed to send HTTP request: %s" % error)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_TIMEOUT:
			print("ERROR: Request timed out after 7 seconds - no response from Ollama server")
		else:
			print("ERROR: HTTP Request failed with result: %s" % result)
		return
	
	if response_code != 200:
		print("ERROR: Server returned error code: %s" % response_code)
		print("Response body: ", body.get_string_from_utf8())
		return
	
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		print("ERROR: Failed to parse JSON response")
		return
	
	var response: Dictionary = json.data
	print("\n=== Ollama Response ===")
	print("Model: ", response.get("model", "unknown"))
	print("Response: ", response.get("response", "No response"))
	print("Done: ", response.get("done", false))
	
	# Print timing info if available
	if response.has("total_duration"):
		print("Total duration: ", response.total_duration / 1_000_000_000.0, " seconds")
