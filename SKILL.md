---
name: youtube-transcript
description: Transcribe YouTube videos locally with Whisper into agent-ready transcripts — no captions, no cloud. Per-channel/domain vocabulary memory makes it more accurate every time the user corrects a term. Use when given a YouTube URL to transcribe, process, summarize, or sync into a knowledge base.
---

# youtube-transcript — a local transcription layer that gets more accurate with use

## Why this exists (vs. off-the-shelf tools)

Off-the-shelf tools solve "video → text". This solves "**the most valuable tokens in the text are wrong, and wrong the same way every time**". A transcript's value concentrates in a few dozen rare tokens — tickers, names, prices, dates — which is exactly where ASR fails. Three differentiators (market gap verified 2026-07):

1. **Whisper is always the path** — existing tools are caption-first, and captions are empirically the inferior tier.
2. **Vocabulary memory loop** — per-channel/domain terms feed Whisper's initial_prompt; correction rules post-process the output. Correct a term once, it stays correct.
3. **Provenance** — every transcript header records the model and ruleset version that produced it; ambiguous tokens get flagged, never guessed.

The transcription mechanics themselves are commodity — **do not invest further engineering there**. If diarization or multi-platform support is ever needed, adopt an existing tool as the backend; the memory layer's interface doesn't change.

## Usage

```bash
bin/yt-transcribe.sh "<youtube-url>" [outdir]
# outdir defaults: ./sources/_inbox (if it exists) > cwd; or set YT_SYNC_OUTDIR
```

Outputs `<date>-<slug>.txt` (YAML header + corrected transcript) and a matching `.srt` (timestamps, for citing back to audio).
Pipeline: yt-dlp download → profile resolution (default → channel → domain) → Whisper (terms in prompt) → layered glossary post-process → output.

One-time install: `./install.sh` (or manually: `brew install yt-dlp ffmpeg whisper-cpp`, then download the model to `~/.whisper/ggml-large-v3-turbo.bin`).

## Memory architecture

```
profiles/                 # vocabulary memory (feeds Whisper initial_prompt, ~224-token cap)
  default.conf            # BASE_PROMPT
  domains/<d>.conf        # DOMAIN_TERMS
  channels/<id>.conf      # CHANNEL_TERMS + DOMAIN declaration; auto-stubbed for new channels
memory/
  corrections.log         # append-only event log (RECORD layer: write freely, errors are harmless)
  glossary/global.sed     # correction rules (BEHAVIOR layer: changes all future output — gated)
  glossary/global.local.sed        # your overlay (gitignored), applied after the public file
  glossary/domains/<d>.sed
  glossary/domains/<d>.local.sed   # your overlay (gitignored)
  glossary/channels/<id>.sed       # channel scope is local-only by nature
tests/golden.tsv          # promotion = test: every rule ships with its evidence sentence
tests/golden.local.tsv    # same, for local-overlay and channel rules (gitignored)
```

Channel profiles, channel glossaries, corrections.log, and all `.local.sed` overlays are **gitignored** — they stay on your machine, and `git pull` never conflicts. Public domain glossaries are a shared seed; **nothing about your setup depends on upstream accepting anything**.

**Scope principle: promote to the narrowest scope where the fix is unambiguous.** The narrower the scope, the more aggressive you may be — `musk→Musk` is dangerous globally (the fragrance) but safe on a channel that covers Tesla weekly. Global should be almost permanently empty.

## Agent duties at sync time (the core of the engineering loop)

When processing a transcript into notes:

1. **Contextual correction**: fix mishearings the glossary can't safely catch (`sequel→SQL`-type real-word collisions) in the notes; annotate inferred fixes (e.g. tickers) with the basis of inference.
2. **Log it**: append every correction to `memory/corrections.log` (TSV format in file header). The user's natural corrections in conversation ("that's X, not Y") count too — **correction is training**.
3. **Check promotion**: the same `wrong→right` in **≥2 distinct videos**, unambiguous at some scope → add the sed rule at that scope's **`.local.sed` overlay** (immediate effect, clean `git pull`) + add the evidence sentence to `tests/golden.local.tsv` + run `tests/run_tests.sh` all-green. New proper nouns promote into profile terms the same way. **Optionally** upstream domain/global rules: open a PR moving the rule + its golden tests into the public files; once merged, delete the local copy. Contribution is purely optional — local overlays are fully functional forever.
4. **Never-promote list**: mishearings that are high-frequency normal words (having, like, …) get logged as `context-only` and stay in the contextual layer forever.

Rule: **an LLM's single guess never writes to the behavior layer.** Promotion = evidence (≥2 videos) + test + git commit, all three.

## Quality discipline (for downstream notes)

- Transcripts are AI-transcribed; notes must state "original audio is authoritative". Ambiguous tickers/names/prices get `[UNSOURCED]`, never a plausible guess.
- Summaries must paraphrase and condense — no bulk copying (copyright).
- Transcript file = Whisper output + mechanical fixes; notes = fully corrected canon. When in doubt, use the .srt timestamps to check the original audio.
- Knowledge-base-specific rules (note formats, prediction ledgers, …) belong to each repo's own instructions, not here.

## Health check (monthly, or on request)

1. **KPI — corrections per video at sync time** (count from the log): falling = memory is learning; flat = mostly one-off noise, fine; rising = a rule may have gone bad, check git history.
2. Log entries stuck >3 months below the promotion threshold → archive with a note.
3. Spot-check recent transcript headers: does glossary_version match git?
4. Prompt length: any profile combination over 900 chars needs trimming (Whisper truncates silently).

## Known limits

- Audio only, no frames (theses and numbers live in the audio track). If visuals are ever needed, adopt a multimodal tool — don't build.
- Quality verified on English single-speaker content (2026-07: 32-min video in ~3 min on an M3 Pro). Other languages/multi-speaker untested; `-l auto` should handle language detection.
- BSD sed (macOS): word boundaries are `[[:<:]]`/`[[:>:]]`, not `\b`.
- yt-dlp blocked → `yt-dlp -U`; if needed `--cookies-from-browser chrome`.
- whisper-cli not found → override with `WHISPER_BIN=`; model path with `WHISPER_MODEL=`.

## Maintainer notes

- Upstream PRs are reviewed best-effort; nothing blocks on review (contributors' rules already work from their local overlays).
- Trigger: when the first external PR arrives, add CI that machine-checks it — touches only `memory/glossary/{global,domains/*}.sed` + `tests/golden.tsv`, every new rule has ≥1 positive and ≥1 negative golden test, BSD sed syntax valid, full test suite green. Review then reduces to a 30-second malicious-pattern skim.
