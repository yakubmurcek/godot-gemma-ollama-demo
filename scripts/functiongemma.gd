extends Node

## Complete function calling test with Ollama + functiongemma.
## Demonstrates the full round-trip: prompt → tool call → execute → response.

const OLLAMA_URL := "http://127.0.0.1:11434/api/chat"
const MODEL := "functiongemma"

var http_request: HTTPRequest
var conversation_messages: Array = [] # Stores the full conversation history
var tools: Array = [] # Tool definitions

func _ready() -> void:
	http_request = HTTPRequest.new()
	http_request.timeout = 30.0
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Define available tools
	tools = _get_tool_definitions()
	
	# Start conversation
	print_rich("[color=cyan]=== Function Calling Test ===[/color]\n")
	send_user_message("What's the weather like in Paris?")


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


#region Simulated Tool Functions
## These simulate real functions - replace with actual implementations!

func execute_tool(function_name: String, arguments: Dictionary) -> String:
	print_rich("[color=yellow]  → Executing: %s(%s)[/color]" % [function_name, arguments])
	
	match function_name:
		"get_weather":
			return _get_weather(arguments)
		"get_time":
			return _get_time(arguments)
		_:
			push_error("Unknown function requested: '%s'" % function_name)
			return "Error: Unknown function '%s'" % function_name


func _get_weather(args: Dictionary) -> String:
	var location: String = args.get("location", "Unknown")
	var unit: String = args.get("unit", "celsius")
	
	# Return structured data - replace with real API call!
	var data := {
		"location": location,
		"temperature": 18 if unit == "celsius" else 64,
		"unit": unit,
		"condition": "partly cloudy",
		"wind": "light"
	}
	return JSON.stringify(data)


func _get_time(args: Dictionary) -> String:
	var timezone: String = args.get("timezone", "UTC")
	
	# Return structured data - replace with real implementation!
	var data := {
		"timezone": timezone,
		"time": "14:32:15",
		"date": "2025-12-27"
	}
	return JSON.stringify(data)


func _sanitize_assistant_message(message: Dictionary) -> Dictionary:
	## Fixes Ollama JSON issue: GDScript sends index as 0.0 (float), but Ollama expects int.
	var sanitized := message.duplicate(true)
	
	if sanitized.has("tool_calls"):
		for i in range(sanitized.tool_calls.size()):
			var tool_call: Dictionary = sanitized.tool_calls[i]
			# Convert any float index to int
			if tool_call.has("index"):
				tool_call["index"] = int(tool_call["index"])
			if tool_call.has("function") and tool_call.function.has("index"):
				tool_call.function["index"] = int(tool_call.function["index"])
	
	return sanitized

#endregion


#region Ollama Communication

func send_user_message(message: String) -> void:
	print_rich("[color=green][User] %s[/color]\n" % message)
	conversation_messages.append({"role": "user", "content": message})
	_send_request()


func send_tool_result(_tool_name: String, result: String) -> void:
	print_rich("[color=magenta]  ← Result: %s[/color]\n" % result)
	conversation_messages.append({"role": "tool", "content": result})
	_send_request()


func _send_request() -> void:
	var body := {
		"model": MODEL,
		"messages": conversation_messages,
		"tools": tools,
		"stream": false
	}
	
	var json_body := JSON.stringify(body)
	var headers := ["Content-Type: application/json"]
	
	var error := http_request.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		push_error("Failed to send HTTP request: %s" % error_string(error))


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("HTTP request failed with result code: %s" % result)
		return
	
	if response_code != 200:
		push_error("HTTP %s: %s" % [response_code, body.get_string_from_utf8()])
		return
	
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("Failed to parse JSON response: %s" % json.get_error_message())
		return
	
	var response: Dictionary = json.data
	var message: Dictionary = response.get("message", {})
	
	# Check if the model wants to call tools
	if message.has("tool_calls") and message.tool_calls.size() > 0:
		print_rich("[color=white][Assistant] Calling tools...[/color]")
		
		# Sanitize and store assistant message - fix float/int issue for index fields
		var sanitized_message := _sanitize_assistant_message(message)
		conversation_messages.append(sanitized_message)
		
		# Process each tool call
		for tool_call in message.tool_calls:
			var func_info: Dictionary = tool_call.get("function", {})
			var func_name: String = func_info.get("name", "")
			var func_args: Dictionary = func_info.get("arguments", {})
			
			# Execute the tool and get result
			var tool_result := execute_tool(func_name, func_args)
			
			# Send result back to LLM for final response
			send_tool_result(func_name, tool_result)
	else:
		# Final response - no more tool calls
		conversation_messages.append(message)
		var content: String = message.get("content", "")
		print_rich("[color=white][Assistant] %s[/color]" % content)
		print_rich("\n[color=cyan]=== Conversation Complete ===[/color]")
		
		if response.has("total_duration"):
			print_rich("[color=gray]Total time: %.2f seconds[/color]" % (response.total_duration / 1_000_000_000.0))

#endregion
