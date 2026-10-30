#!/usr/bin/env bash
# PreToolUse(Bash): два запрета по простому паттерну, без разбора команды.
# «git» ищется в начале команды или после ; & | ( — текст в кавычках
# (echo, grep) не считается. Защита от обхода не цель: для этого есть сервер.
set -u

payload=$(cat)
. "$(cd "$(dirname "$0")" && pwd)/lib/json-field.sh"
cmd=$(json_field "$payload" "tool_input.command" "")
[ -n "$cmd" ] || exit 0
# Тело heredoc не проверяем: там документация, а не команды. Заодно не
# проверяется всё после первого «<<», включая команды за heredoc: защита
# от обхода не цель.
cmd=${cmd%%<<*}

git_at_start='(^|[;&|(][[:space:]]*)git[[:space:]]'
if printf '%s' "$cmd" | grep -Eq "${git_at_start}.*--no-verify"; then
  echo "Запрещено: --no-verify обходит проверки. Почини причину, а не обходи гейт." >&2
  exit 2
fi

if printf '%s' "$cmd" | grep -Eq "${git_at_start}+push" \
  && printf '%s' "$cmd" | grep -Eq -- '(--force|[[:space:]]-f([[:space:]]|$)|[[:space:]]\+)' \
  && printf '%s' "$cmd" | grep -Eq '(^|[[:space:]:/+])(main|master)([[:space:];)]|$)'; then
  echo "Запрещено: force push в main/master." >&2
  exit 2
fi
exit 0
