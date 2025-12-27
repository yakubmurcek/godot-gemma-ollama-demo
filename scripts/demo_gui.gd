extends Control

## Interactive demo GUI for Ollama + Gemma models.
## Shows conversation, tool calls, errors, and timing.

const GENERATE_URL := "http://127.0.0.1:11434/api/generate"
const CHAT_URL := "http://127.0.0.1:11434/api/chat"
const TIMEOUT := 30.0

enum Model {GEMMA3, FUNCTIONGEMMA}

var _http_request: HTTPRequest
var _current_model: Model = Model.FUNCTIONGEMMA
var _messages: Array = []
var _start_time: int = 0
var _is_waiting: bool = false

# Tool definitions for functiongemma
var _tools: Array = [
	{
		"type": "function",
		"function": {
			"name": "get_weather",
			"description": "Get the current weather for a location",
			"parameters": {
				"type": "object",
				"properties": {
					"location": {"type": "string", "description": "The city and country"},
					"unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
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
					"timezone": {"type": "string", "description": "The timezone, e.g. Europe/Paris"}
				},
				"required": ["timezone"]
			}
		}
	}
]

# UI References
@onready var model_selector: OptionButton = %ModelSelector
@onready var conversation_display: RichTextLabel = %ConversationDisplay
@onready var prompt_input: LineEdit = %PromptInput
@onready var send_button: Button = %SendButton
@onready var status_label: Label = %StatusLabel
@onready var clear_button: Button = %ClearButton


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = TIMEOUT
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	# Setup model selector
	model_selector.add_item("functiongemma (tool calling)", Model.FUNCTIONGEMMA)
	model_selector.add_item("gemma3:1b (simple chat)", Model.GEMMA3)
	model_selector.item_selected.connect(_on_model_selected)
	
	# Setup input
	send_button.pressed.connect(_on_send_pressed)
	prompt_input.text_submitted.connect(_on_prompt_submitted)
	clear_button.pressed.connect(_on_clear_pressed)
	
	_update_status("Ready")
	_append_system("Welcome! Select a model and send a message.")


func _on_model_selected(index: int) -> void:
	_current_model = model_selector.get_item_id(index) as Model
	_messages.clear()
	_append_system("Switched to %s" % _get_model_name())


func _on_send_pressed() -> void:
	_send_current_prompt()


func _on_prompt_submitted(_text: String) -> void:
	_send_current_prompt()


func _on_clear_pressed() -> void:
	_messages.clear()
	conversation_display.clear()
	_append_system("Conversation cleared.")
	_update_status("Ready")


func _send_current_prompt() -> void:
	var prompt := prompt_input.text.strip_edges()
	if prompt.is_empty() or _is_waiting:
		return
	
	prompt_input.text = ""
	_append_user(prompt)
	_messages.append({"role": "user", "content": prompt})
	_start_time = Time.get_ticks_msec()
	_send_request()


func _send_request() -> void:
	_is_waiting = true
	_update_status("Waiting for response...")
	send_button.disabled = true
	
	var body: Dictionary
	var url: String
	
	if _current_model == Model.GEMMA3:
		url = GENERATE_URL
		body = {
			"model": "gemma3:1b",
			"prompt": _messages[-1].content,
			"stream": false
		}
	else:
		url = CHAT_URL
		body = {
			"model": "functiongemma",
			"messages": _messages,
			"tools": _tools,
			"stream": false
		}
	
	var error := _http_request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_append_error("Failed to send request: %s" % error_string(error))
		_finish_request()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_TIMEOUT:
			_append_error("Request timed out - is Ollama running?")
		else:
			_append_error("HTTP request failed: %s" % result)
		_finish_request()
		return
	
	if response_code != 200:
		_append_error("HTTP %s: %s" % [response_code, body.get_string_from_utf8()])
		_finish_request()
		return
	
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_append_error("JSON parse error: %s" % json.get_error_message())
		_finish_request()
		return
	
	var response: Dictionary = json.data
	
	if _current_model == Model.GEMMA3:
		_handle_generate_response(response)
	else:
		_handle_chat_response(response)


func _handle_generate_response(response: Dictionary) -> void:
	var text: String = response.get("response", "")
	_append_assistant(text)
	_finish_request(response)


func _handle_chat_response(response: Dictionary) -> void:
	var message: Dictionary = response.get("message", {})
	
	if message.has("tool_calls") and message.tool_calls.size() > 0:
		_append_assistant("Calling tools...")
		_messages.append(_sanitize_message(message))
		
		for tool_call in message.tool_calls:
			var func_info: Dictionary = tool_call.get("function", {})
			var func_name: String = func_info.get("name", "")
			var func_args: Dictionary = func_info.get("arguments", {})
			
			_append_tool_call(func_name, func_args)
			var tool_result := _execute_tool(func_name, func_args)
			_append_tool_result(tool_result)
			_messages.append({"role": "tool", "content": tool_result})
		
		# Continue conversation to get final response
		_send_request()
	else:
		_messages.append(message)
		_append_assistant(message.get("content", ""))
		_finish_request(response)


func _finish_request(response: Dictionary = {}) -> void:
	_is_waiting = false
	send_button.disabled = false
	
	var elapsed := (Time.get_ticks_msec() - _start_time) / 1000.0
	var status := "Done in %.2fs" % elapsed
	
	if response.has("total_duration"):
		var model_time: float = response.total_duration / 1_000_000_000.0
		status += " (model: %.2fs)" % model_time
	
	_update_status(status)


#region Tool Implementations

func _execute_tool(func_name: String, args: Dictionary) -> String:
	match func_name:
		"get_weather":
			var location: String = args.get("location", "Unknown")
			var unit: String = args.get("unit", "celsius")
			return JSON.stringify({
				"location": location,
				"temperature": 18 if unit == "celsius" else 64,
				"unit": unit,
				"condition": "partly cloudy"
			})
		"get_time":
			var timezone: String = args.get("timezone", "UTC")
			var now := Time.get_datetime_dict_from_system()
			return JSON.stringify({
				"timezone": timezone,
				"time": "%02d:%02d:%02d" % [now.hour, now.minute, now.second],
				"date": "%04d-%02d-%02d" % [now.year, now.month, now.day]
			})
		_:
			return '{"error": "Unknown function: %s"}' % func_name

#endregion


#region UI Helpers

func _append_user(text: String) -> void:
	conversation_display.append_text("[color=lime][b]You:[/b][/color] %s\n\n" % text)


func _append_assistant(text: String) -> void:
	conversation_display.append_text("[color=white][b]Assistant:[/b][/color] %s\n\n" % text)


func _append_tool_call(func_name: String, args: Dictionary) -> void:
	conversation_display.append_text("[color=yellow]  → [b]%s[/b](%s)[/color]\n" % [func_name, args])


func _append_tool_result(result: String) -> void:
	conversation_display.append_text("[color=magenta]  ← %s[/color]\n\n" % result)


func _append_error(text: String) -> void:
	conversation_display.append_text("[color=red][b]Error:[/b] %s[/color]\n\n" % text)


func _append_system(text: String) -> void:
	conversation_display.append_text("[color=gray][i]%s[/i][/color]\n\n" % text)


func _update_status(text: String) -> void:
	status_label.text = text


func _get_model_name() -> String:
	return "functiongemma" if _current_model == Model.FUNCTIONGEMMA else "gemma3:1b"


func _sanitize_message(message: Dictionary) -> Dictionary:
	var sanitized := message.duplicate(true)
	if sanitized.has("tool_calls"):
		for tool_call in sanitized.tool_calls:
			if tool_call.has("index"):
				tool_call["index"] = int(tool_call["index"])
			if tool_call.has("function") and tool_call.function.has("index"):
				tool_call.function["index"] = int(tool_call.function["index"])
	return sanitized

#endregion
