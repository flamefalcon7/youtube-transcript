#!/usr/bin/env bash
# youtube-transcript — transcribe YouTube videos locally into agent-ready transcripts.
# Generic core: domain knowledge lives in profiles/ and memory/, not here.
# Usage: yt-transcribe.sh <youtube-url> [outdir]
# Deps:  yt-dlp, ffmpeg, whisper-cli (brew install yt-dlp ffmpeg whisper-cpp)
#        Whisper model (default ~/.whisper/ggml-large-v3-turbo.bin)
set -euo pipefail

URL="${1:?usage: yt-transcribe.sh <youtube-url> [outdir]}"

# --- Config -----------------------------------------------------------
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_MODEL="${WHISPER_MODEL:-$HOME/.whisper/ggml-large-v3-turbo.bin}"
WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"
# Output dir: arg > $YT_SYNC_OUTDIR > ./sources/_inbox (if present, for knowledge-base repos) > cwd
if [ -n "${2:-}" ]; then OUTDIR="$2"
elif [ -n "${YT_SYNC_OUTDIR:-}" ]; then OUTDIR="$YT_SYNC_OUTDIR"
elif [ -d "$PWD/sources/_inbox" ]; then OUTDIR="$PWD/sources/_inbox"
else OUTDIR="$PWD"
fi
# ----------------------------------------------------------------------

for bin in yt-dlp ffmpeg "$WHISPER_BIN"; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing $bin — see SKILL.md for install" >&2; exit 1; }
done
[ -f "$WHISPER_MODEL" ] || { echo "model not found: ${WHISPER_MODEL} (see SKILL.md for download)" >&2; exit 1; }

mkdir -p "$OUTDIR"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "→ fetching video metadata…"
META="$(yt-dlp --no-warnings --print '%(id)s|%(channel_id)s|%(channel)s|%(upload_date)s|%(title)s' "$URL" | head -1)"
VID="${META%%|*}";        REST="${META#*|}"
CHANNEL_ID="${REST%%|*}"; REST="${REST#*|}"
CHANNEL="${REST%%|*}";    REST="${REST#*|}"
UPDATE="${REST%%|*}"
TITLE="${REST#*|}"
ISO="${UPDATE:0:4}-${UPDATE:4:2}-${UPDATE:6:2}"
SLUG="$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-50)"
OUT="$OUTDIR/${ISO}-${SLUG:-$VID}.txt"

# --- Profile resolution: default → channel (may declare DOMAIN) → domain ---
BASE_PROMPT="Transcript of a spoken-word video."
DOMAIN=""; DOMAIN_TERMS=""; CHANNEL_TERMS=""
# shellcheck source=/dev/null
[ -f "$SKILL_DIR/profiles/default.conf" ] && . "$SKILL_DIR/profiles/default.conf"
CHAN_CONF="$SKILL_DIR/profiles/channels/$CHANNEL_ID.conf"
if [ -f "$CHAN_CONF" ]; then
  . "$CHAN_CONF"
else
  # New channel: auto-create a stub (zero questions asked); terms accrue via sync corrections.
  { echo "# ${CHANNEL} (auto-created $(date +%F))"
    echo "# DOMAIN=<domain>  # maps to profiles/domains/<domain>.conf — uncomment once known"
    echo "CHANNEL_TERMS=\"\""
  } > "$CHAN_CONF"
  echo "→ new channel — created profile stub: profiles/channels/$CHANNEL_ID.conf"
fi
[ -n "$DOMAIN" ] && [ -f "$SKILL_DIR/profiles/domains/$DOMAIN.conf" ] && . "$SKILL_DIR/profiles/domains/$DOMAIN.conf"

PROMPT="$BASE_PROMPT"
TERMS="$(echo "$DOMAIN_TERMS $CHANNEL_TERMS" | xargs || true)"
[ -n "$TERMS" ] && PROMPT="$BASE_PROMPT Terms: $TERMS."
if [ "${#PROMPT}" -gt 900 ]; then
  echo "⚠ prompt is ${#PROMPT} chars (Whisper initial_prompt caps at ~224 tokens) — trim profile terms or the tail gets silently truncated" >&2
fi

echo "→ downloading audio…"
yt-dlp --no-warnings -f bestaudio -x --audio-format wav \
  --postprocessor-args "-ar 16000 -ac 1" -o "$TMP/audio.%(ext)s" "$URL" >/dev/null

echo "→ transcribing ($(basename "$WHISPER_MODEL" .bin))…"
"$WHISPER_BIN" -m "$WHISPER_MODEL" -f "$TMP/audio.wav" -l auto \
  --prompt "$PROMPT" -otxt -osrt -of "$TMP/tx" >/dev/null 2>&1

# --- Post-process: layered glossaries (global → domain → channel; narrow last, may override) ---
# Each public scope has a gitignored .local.sed overlay: promotions land there first so the
# clone stays clean against origin; contributing upstream via PR is optional.
NCORR=0
GLOSSARIES=("$SKILL_DIR/memory/glossary/global.sed" "$SKILL_DIR/memory/glossary/global.local.sed")
[ -n "$DOMAIN" ] && GLOSSARIES+=("$SKILL_DIR/memory/glossary/domains/$DOMAIN.sed" "$SKILL_DIR/memory/glossary/domains/$DOMAIN.local.sed")
GLOSSARIES+=("$SKILL_DIR/memory/glossary/channels/$CHANNEL_ID.sed")
for g in "${GLOSSARIES[@]}"; do
  [ -f "$g" ] || continue
  for f in tx.txt tx.srt; do
    sed -f "$g" "$TMP/$f" > "$TMP/$f.new"
    if [ "$f" = "tx.txt" ]; then
      n="$(diff "$TMP/$f" "$TMP/$f.new" | grep -c '^<' || true)"
      NCORR=$((NCORR + n))
    fi
    mv "$TMP/$f.new" "$TMP/$f"
  done
done
echo "→ glossary post-process: $NCORR lines corrected (scope: global$( [ -n "$DOMAIN" ] && echo "+$DOMAIN")+channel)"

GLOSSARY_VER="$(git -C "$SKILL_DIR" rev-parse --short HEAD 2>/dev/null || echo uncommitted)"

{
  echo "---"
  echo "url: $URL"
  echo "video_id: $VID"
  echo "channel: $CHANNEL"
  echo "channel_id: $CHANNEL_ID"
  echo "title: $TITLE"
  echo "upload_date: $ISO"
  echo "transcript_source: whisper $(basename "$WHISPER_MODEL" .bin) (AI transcription — original audio is authoritative)"
  echo "profile: default$( [ -n "$DOMAIN" ] && echo "+$DOMAIN")+channel"
  echo "glossary_version: ${GLOSSARY_VER} (${NCORR} lines corrected)"
  echo "---"
  echo
  cat "$TMP/tx.txt"
} > "$OUT"
cp "$TMP/tx.srt" "${OUT%.txt}.srt"

echo "✓ done: $OUT"
echo "  timestamped: ${OUT%.txt}.srt (for citing back to audio positions)"
echo "  next: have your agent process it; log corrections per SKILL.md into memory/corrections.log."
