#!/usr/bin/env bash
# UserPromptSubmit: запоминаем время начала хода, чтобы уведомление
# «задача завершена» приходило только после долгих ходов.
set -u

payload=$(cat)
. "$(cd "$(dirname "$0")" && pwd)/lib/json-field.sh"
. "$(cd "$(dirname "$0")" && pwd)/lib/notify.sh"
sid=$(json_field "$payload" "session_id" "")
[ -n "$sid" ] || exit 0

mkdir -p "$(notify_state_dir)"
date +%s > "$(notify_ts_file "$sid")"
exit 0
