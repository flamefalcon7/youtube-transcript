# youtube-transcript

**A local YouTube transcription skill for AI agents that gets more accurate every time you correct it.**

Built on the open [agent skills standard](https://developers.openai.com/codex/skills) (`SKILL.md`) — works with **Claude Code**, **OpenAI Codex CLI**, and any harness that reads the format (GitHub Copilot, Cursor, Windsurf, OpenClaw, …). `install.sh` auto-registers it with every harness on your machine. 100% local: yt-dlp → ffmpeg → whisper.cpp. No captions, no cloud, no API keys, your data never leaves the machine.

## The pain point

Every tool can turn a video into text. But a transcript's value concentrates in a few dozen rare tokens — tickers, names, prices, project names — and that's exactly where speech recognition fails. If your agent acts on the transcript (research notes, prediction ledgers, decisions), one misheard token becomes a confident, well-formatted error in your knowledge base.

Worse: the errors are *stable*. Whisper mishears the same domain terms the same way in every video, and no existing tool accumulates your corrections. You fix "Kubernets" to "Kubernetes" forever.

**Real case** (32-min finance interview): YouTube's auto-captions got the video title wrong, rendered a company name so ambiguously the sentence had two readings, and dropped an entire segment. Generic Whisper fixed all of that — but still mangled ticker symbols, a CEO's surname (rendered as a common noun), and a recurring industry term, identically in every video from that channel. After one correction pass, all of these are fixed automatically in every future video.

## How it works

```
bin/yt-transcribe.sh "<youtube-url>"
```

1. **Profile resolution** — the channel ID selects vocabulary (channel terms → domain terms), which feeds Whisper's `initial_prompt`. New channels get a stub automatically.
2. **Whisper transcription** — always Whisper, never captions. `large-v3-turbo` runs a 32-min video in ~3 min on an M3 Pro.
3. **Layered glossary post-process** — deterministic corrections at three scopes (global → domain → channel), narrow scope wins.
4. **Output** — `.txt` with a provenance header (model, profile chain, glossary version, corrections applied) + `.srt` for citing back to audio positions.

## The memory loop

```
transcribe → agent fixes remaining mishearings contextually at sync time
          → every fix is appended to memory/corrections.log   (record layer: free)
          → same fix seen in ≥2 videos + unambiguous + test passes
          → promoted to glossary/profile                      (behavior layer: gated)
          → next video is more accurate
```

The gate matters: **an LLM's single guess never changes future behavior.** Promotion requires evidence across videos, a golden test (the evidence sentence itself), and a git commit. Ambiguity is scope-relative — `musk→Musk` is unsafe globally (the fragrance) but safe on a channel that covers Tesla weekly — so rules promote to the narrowest unambiguous scope.

Your channel profiles and correction log encode your viewing history; they're gitignored and stay local. Domain-level promotions land in gitignored `.local.sed` overlays — they take effect immediately and `git pull` never conflicts. **Nothing depends on upstream**: contributing a rule back via PR is optional and reviewed best-effort; your setup works identically either way.

## Install

```bash
git clone https://github.com/flamefalcon7/youtube-transcript
cd youtube-transcript && ./install.sh
# brew deps + model download (~1.5GB) + auto-registers with Claude Code (~/.claude/skills),
# Codex (~/.codex/skills), and the open-standard location (~/.agents/skills) via symlink
```

Then give your agent a YouTube URL, or run `bin/yt-transcribe.sh "<url>"` directly.
Requirements: macOS (BSD sed; Apple Silicon recommended), [Homebrew](https://brew.sh).

## What this is not

- Not a captions fetcher — if you just need YouTube's captions fast, use any of the many caption tools.
- Not a video understanding tool — audio only, by design. Theses and numbers live in the audio track.
- Not a transcription service — it's a *skill*: the agent-facing workflow (memory, corrections, provenance, tests) around a deliberately replaceable transcription core.

## License

MIT
