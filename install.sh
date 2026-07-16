#!/usr/bin/env bash
# One-shot setup: brew deps + Whisper model download.
set -euo pipefail

command -v brew >/dev/null 2>&1 || { echo "Homebrew required: https://brew.sh" >&2; exit 1; }

echo "→ installing dependencies (yt-dlp, ffmpeg, whisper-cpp)…"
for pkg in yt-dlp ffmpeg whisper-cpp; do
  brew list "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done

MODEL="$HOME/.whisper/ggml-large-v3-turbo.bin"
if [ -f "$MODEL" ]; then
  echo "→ model already present: $MODEL"
else
  echo "→ downloading Whisper model (~1.5GB) to $MODEL…"
  mkdir -p "$HOME/.whisper"
  curl -L --progress-bar -o "$MODEL" \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
fi

echo "→ running glossary tests…"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SKILL_DIR/tests/run_tests.sh"

# Wire the skill into every agent harness present on this machine (SKILL.md is the
# open agent-skills standard: Claude Code, OpenAI Codex, and others discover it there).
echo "→ registering with agent harnesses…"
LINKED=0
for dir in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills"; do
  parent="$(dirname "$dir")"
  [ -d "$parent" ] || continue          # only harnesses actually installed
  mkdir -p "$dir"
  target="$dir/$(basename "$SKILL_DIR")"
  if [ "$target" != "$SKILL_DIR" ]; then
    ln -sfn "$SKILL_DIR" "$target"
  fi
  echo "  ✓ $target"
  LINKED=$((LINKED+1))
done
if [ "$LINKED" -eq 0 ]; then
  mkdir -p "$HOME/.agents/skills"
  ln -sfn "$SKILL_DIR" "$HOME/.agents/skills/$(basename "$SKILL_DIR")"
  echo "  ✓ $HOME/.agents/skills/$(basename "$SKILL_DIR") (open-standard location)"
fi

echo "✓ ready. Try: bin/yt-transcribe.sh \"<youtube-url>\" — or just give your agent a YouTube URL."
