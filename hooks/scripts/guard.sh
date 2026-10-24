#!/usr/bin/env bash
# PreToolUse(Bash): два запрета по простому паттерну, без разбора команды.
# Ложное срабатывание на echo/grep с этими словами — приемлемая цена:
# агент переформулирует. Защита от обхода не цель: для этого есть сервер.
set -u

payload=$(cat)
. "$(cd "$(dirname "$0")" && pwd)/lib/json-field.sh"
cmd=$(json_field "$payload" "tool_input.command" "")
[ -n "$cmd" ] || exit 0
# Тело heredoc не проверяем: там документация, а не команды.
cmd=${cmd%%<<*}

if printf '%s' "$cmd" | grep -Eq 'git[[:space:]].*--no-verify'; then
  echo "Запрещено: --no-verify обходит проверки. Почини причину, а не обходи гейт." >&2
  exit 2
fi

if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push' \
  && printf '%s' "$cmd" | grep -Eq -- '(--force|[[:space:]]-f([[:space:]]|$)|[[:space:]]\+)' \
  && printf '%s' "$cmd" | grep -Eq '(^|[[:space:]:/+])(main|master)([[:space:]]|$)'; then
  echo "Запрещено: force push в main/master." >&2
  exit 2
fi
exit 0
