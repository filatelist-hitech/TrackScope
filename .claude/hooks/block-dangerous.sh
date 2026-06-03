#!/usr/bin/env bash
# PreToolUse hook — blocks dangerous Bash commands not already covered by permissions.deny
# Receives JSON on stdin: {"session_id":"...","tool_name":"Bash","tool_input":{"command":"..."}}
# Exit 2 = block (stdout shown to Claude as reason)

INPUT="$(cat)"
TOOL="$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null)"

[ "$TOOL" != "Bash" ] && exit 0

CMD="$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)"

block() {
  echo "BLOCKED: $1. This command is prohibited by project safety policy."
  exit 2
}

echo "$CMD" | grep -qE 'sudo[[:space:]]+rm' && block "sudo rm"
echo "$CMD" | grep -qE 'chmod[[:space:]]+777' && block "chmod 777"
echo "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+.*--force' && block "git push --force"
echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard' && block "git reset --hard"
echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-f' && block "git clean -f"
echo "$CMD" | grep -qE 'rm[[:space:]]+-rf[[:space:]]+[./~]' && block "rm -rf on root/home/relative path"

exit 0
