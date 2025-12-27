extends Node

## Quick test script for Ollama API with functiongemma model (tool calling).
## Attach this to any Node and run the scene to test.

const OLLAMA_URL := "http://127.0.0.1:11434/api/chat"
const MODEL := "functiongemma"

var http_request: HTTPRequest

func _ready() -> void:
	# Create HTTP request node
	http_request = HTTPRequest.new()
	http_request.timeout = 30.0 # Longer timeout for function calling
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Test prompts for function calling
	send_chat_with_tools("What's the weather like in Paris?")

func send_chat_with_tools(user_message: String) -> void:
	# Define available tools (functions the model can call)
	var tools := [
		{
			"type": "function",
			"function": {
				"name": "get_weather",
				"description": "Get the current weather for a location",
				"parameters": {
					"type": "object",
					"properties": {
						"location": {
							"type": "string",
							"description": "The city and country, e.g. Paris, France"
						},
						"unit": {
							"type": "string",
							"enum": ["celsius", "fahrenheit"],
							"description": "Temperature unit"
						}
					},
					"required": ["location"]
				}
			}
		},
		{
			"type": "function",
			"function": {
				"name": "get_time",
				"description": "Get the current time for a timezone",
				"parameters": {
					"type": "object",
					"properties": {
						"timezone": {
							"type": "string",
							"description": "The timezone, e.g. Europe/Paris"
						}
					},
					"required": ["timezone"]
				}
			}
		}
	]
	
	var body := {
		"model": MODEL,
		"messages": [
			{"role": "user", "content": user_message}
		],
		"tools": tools,
		"stream": false
	}
	
	var json_body := JSON.stringify(body)
	var headers := ["Content-Type: application/json"]
	
	print("Sending request to Ollama (functiongemma)...")
	print("User message: ", user_message)
	print("Available tools: get_weather, get_time")
	
	var error := http_request.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		print("ERROR: Failed to send HTTP request: %s" % error)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_TIMEOUT:
			print("ERROR: Request timed out - no response from Ollama server")
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
	
	# Get the message from the response
	var message: Dictionary = response.get("message", {})
	
	# Check if the model wants to call a tool
	if message.has("tool_calls"):
		print("\n--- Tool Calls ---")
		var tool_calls: Array = message.get("tool_calls", [])
		for tool_call in tool_calls:
			var func_info: Dictionary = tool_call.get("function", {})
			print("Function: ", func_info.get("name", "unknown"))
			print("Arguments: ", func_info.get("arguments", {}))
	else:
		# Regular text response
		print("Content: ", message.get("content", "No content"))
	
	print("\nDone: ", response.get("done", false))
	
	# Print timing info if available
	if response.has("total_duration"):
		print("Total duration: ", response.total_duration / 1_000_000_000.0, " seconds")
