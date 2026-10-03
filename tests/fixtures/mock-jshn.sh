#!/bin/sh
# mock-jshn.sh — minimal OpenWrt jshn.sh replacement for unit/contract tests

_JSON_TMP_FILE="/tmp/mock_jshn_$$.py"

json_init() {
	cat <<'PYEOF' > "$_JSON_TMP_FILE"
import sys, json, base64

stack = [{}]
def cur():
    return stack[-1]

for line in sys.stdin:
    line = line.rstrip('\n')
    if not line:
        continue
    cmd, *args = line.split('\t')
    if cmd == 'add_str_b64':
        k, v_b64 = args[0], (args[1] if len(args) > 1 else '')
        v = base64.b64decode(v_b64).decode('utf-8', errors='replace') if v_b64 else ''
        c = cur()
        if isinstance(c, list):
            c.append(v)
        else:
            c[k] = v
    elif cmd == 'add_int':
        k, v = args[0], int(args[1]) if len(args) > 1 and args[1] else 0
        c = cur()
        if isinstance(c, list):
            c.append(v)
        else:
            c[k] = v
    elif cmd == 'add_bool':
        k, v = args[0], (args[1] == '1' or args[1] == 'true')
        c = cur()
        if isinstance(c, list):
            c.append(v)
        else:
            c[k] = v
    elif cmd == 'start_obj':
        name = args[0] if args else ''
        new_obj = {}
        c = cur()
        if isinstance(c, list):
            c.append(new_obj)
        elif name:
            c[name] = new_obj
        stack.append(new_obj)
    elif cmd == 'close_obj':
        if len(stack) > 1:
            stack.pop()
    elif cmd == 'start_arr':
        name = args[0] if args else ''
        new_arr = []
        c = cur()
        if isinstance(c, list):
            c.append(new_arr)
        elif name:
            c[name] = new_arr
        stack.append(new_arr)
    elif cmd == 'close_arr':
        if len(stack) > 1:
            stack.pop()

print(json.dumps(stack[0]))
PYEOF
	_JSON_CMDS=""
}

json_add_string() {
	b64=$(printf '%s' "${2:-}" | base64 | tr -d '\n')
	_JSON_CMDS="${_JSON_CMDS}add_str_b64	${1:-}	$b64
"
}

json_add_int() {
	_JSON_CMDS="${_JSON_CMDS}add_int	${1:-}	${2:-0}
"
}

json_add_boolean() {
	_JSON_CMDS="${_JSON_CMDS}add_bool	${1:-}	${2:-0}
"
}

json_add_object() {
	_JSON_CMDS="${_JSON_CMDS}start_obj	${1:-}
"
}

json_close_object() {
	_JSON_CMDS="${_JSON_CMDS}close_obj
"
}

json_add_array() {
	_JSON_CMDS="${_JSON_CMDS}start_arr	${1:-}
"
}

json_close_array() {
	_JSON_CMDS="${_JSON_CMDS}close_arr
"
}

json_dump() {
	printf '%s' "$_JSON_CMDS" | python3 "$_JSON_TMP_FILE"
	rm -f "$_JSON_TMP_FILE"
}

json_load() {
	_JSON_LOADED="$1"
	return 0
}

json_get_var() {
	var_name="$1"
	json_key="$2"
	val=$(python3 -c "import json, sys; d=json.loads('''$_JSON_LOADED'''); print(d.get('$json_key', ''))" 2>/dev/null || true)
	eval "$var_name=\"\$val\""
}
