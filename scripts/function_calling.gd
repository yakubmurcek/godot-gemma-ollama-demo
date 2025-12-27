extends Node

## Function calling demo with Ollama + Functiongemma.
## Demonstrates the full round-trip: prompt → tool call → execute → response.
##
## Usage:
##   1. Make sure Ollama is running and accessible
##   2. Pull the model in Ollama: ollama pull functiongemma
##   3. Attach this script to a Node and run the scene

const OLLAMA_URL := "http://127.0.0.1:11434/api/chat"
const MODEL := "functiongemma"
const TIMEOUT := 30.0

var _http_request: HTTPRequest
var _messages: Array = []
var _tools: Array = []


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = TIMEOUT
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	_tools = _get_tool_definitions()
	
	# Demo: Ask about weather (triggers tool call)
	print_rich("[color=cyan]=== Function Calling Demo ===[/color]\n")
	send_message("What's the weather like in Paris?")


#region Tool Definitions

func _get_tool_definitions() -> Array:
	return [
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
							"description": "Temperature unit (default: celsius)"
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

#endregion


#region Tool Implementations
## Replace these with real implementations!

func _execute_tool(func_name: String, args: Dictionary) -> String:
	print_rich("[color=yellow]  → Executing: %s(%s)[/color]" % [func_name, args])
	
	match func_name:
		"get_weather":
			return _get_weather(args)
		"get_time":
			return _get_time(args)
		_:
			return '{"error": "Unknown function: %s"}' % func_name


func _get_weather(args: Dictionary) -> String:
	var location: String = args.get("location", "Unknown")
	var unit: String = args.get("unit", "celsius")
	# Simulated response - replace with real weather API!
	return JSON.stringify({
		"location": location,
		"temperature": 18 if unit == "celsius" else 64,
		"unit": unit,
		"condition": "partly cloudy"
	})


func _get_time(args: Dictionary) -> String:
	var timezone: String = args.get("timezone", "UTC")
	# Simulated response - replace with real time API!
	var now := Time.get_datetime_dict_from_system()
	return JSON.stringify({
		"timezone": timezone,
		"time": "%02d:%02d:%02d" % [now.hour, now.minute, now.second],
		"date": "%04d-%02d-%02d" % [now.year, now.month, now.day]
	})

#endregion


#region Ollama Communication

func send_message(content: String) -> void:
	print_rich("[color=green][User] %s[/color]\n" % content)
	_messages.append({"role": "user", "content": content})
	_send_request()


func _send_tool_result(result: String) -> void:
	print_rich("[color=magenta]  ← Result: %s[/color]\n" % result)
	_messages.append({"role": "tool", "content": result})
	_send_request()


func _send_request() -> void:
	var body := {
		"model": MODEL,
		"messages": _messages,
		"tools": _tools,
		"stream": false
	}
	
	var error := _http_request.request(
		OLLAMA_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
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
	var message: Dictionary = response.get("message", {})
	
	# Check if model wants to call tools
	if message.has("tool_calls") and message.tool_calls.size() > 0:
		print_rich("[color=white][Assistant] Calling tools...[/color]")
		_messages.append(_sanitize_message(message))
		
		for tool_call in message.tool_calls:
			var func_info: Dictionary = tool_call.get("function", {})
			var func_name: String = func_info.get("name", "")
			var func_args: Dictionary = func_info.get("arguments", {})
			var tool_result := _execute_tool(func_name, func_args)
			_send_tool_result(tool_result)
	else:
		# Final response
		_messages.append(message)
		print_rich("[color=white][Assistant] %s[/color]" % message.get("content", ""))
		print_rich("\n[color=cyan]=== Complete ===[/color]")
		
		if response.has("total_duration"):
			print_rich("[color=gray]Time: %.2fs[/color]" % (response.total_duration / 1_000_000_000.0))


func _sanitize_message(message: Dictionary) -> Dictionary:
	## Fixes Ollama JSON issue: GDScript floats vs expected ints in index fields.
	var sanitized := message.duplicate(true)
	if sanitized.has("tool_calls"):
		for tool_call in sanitized.tool_calls:
			if tool_call.has("index"):
				tool_call["index"] = int(tool_call["index"])
			if tool_call.has("function") and tool_call.function.has("index"):
				tool_call.function["index"] = int(tool_call.function["index"])
	return sanitized

#endregion
