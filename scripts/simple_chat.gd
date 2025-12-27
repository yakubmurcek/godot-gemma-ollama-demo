extends Node

## Simple text generation demo with Ollama + Gemma3.
## Demonstrates basic prompt → response flow.
##
## Usage:
##   1. Make sure Ollama is running and accessible
##   2. Pull the model in Ollama: ollama pull gemma3:1b
##   3. Attach this script to a Node and run the scene

const OLLAMA_URL := "http://127.0.0.1:11434/api/generate"
const MODEL := "gemma3:1b"
const TIMEOUT := 30.0

var _http_request: HTTPRequest


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = TIMEOUT
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	# Demo: Send a simple prompt
	print_rich("[color=cyan]=== Simple Chat Demo ===[/color]\n")
	send_prompt("Hello! Tell me a fun fact about space in one sentence.")


## Send a prompt to the Ollama API and get a text response.
func send_prompt(prompt: String) -> void:
	print_rich("[color=green][User] %s[/color]\n" % prompt)
	
	var body := {
		"model": MODEL,
		"prompt": prompt,
		"stream": false
	}
	
	var json_body := JSON.stringify(body)
	var headers := ["Content-Type: application/json"]
	
	var error := _http_request.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		push_error("Failed to send HTTP request: %s" % error_string(error))


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_TIMEOUT:
			push_error("Request timed out - is Ollama running?")
		else:
			push_error("HTTP request failed: %s" % result)
		return
	
	if response_code != 200:
		push_error("HTTP %s: %s" % [response_code, body.get_string_from_utf8()])
		return
	
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("Failed to parse JSON: %s" % json.get_error_message())
		return
	
	var response: Dictionary = json.data
	var text: String = response.get("response", "")
	
	print_rich("[color=white][Assistant] %s[/color]" % text)
	print_rich("\n[color=cyan]=== Complete ===[/color]")
	
	if response.has("total_duration"):
		print_rich("[color=gray]Time: %.2fs[/color]" % (response.total_duration / 1_000_000_000.0))
