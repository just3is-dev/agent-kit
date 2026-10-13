#!/usr/bin/env bash
# json_field <payload> <путь.через.точку> [дефолт]
# Достаёт поле из JSON-payload хука. Возвращает дефолт, если пути нет
# или payload не разбирается. Булевы поля приходят как "True"/"False".
json_field() {
  local payload="$1" path="$2" default="${3:-}"
  printf '%s' "$payload" | python3 -c '
import json, sys

path = sys.argv[1]
default = sys.argv[2]
try:
    d = json.load(sys.stdin)
    for key in path.split("."):
        d = d.get(key) if isinstance(d, dict) else None
        if d is None:
            break
    print(default if d is None else d)
except Exception:
    print(default)
' "$path" "$default"
}
