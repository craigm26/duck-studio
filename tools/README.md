# tools

## claudebridge.mjs

Puts Claude behind an OpenAI-compatible endpoint, using the Claude Code
subscription already signed in on the machine you run it on.

**Why it exists.** Duck Studio drafts against anything speaking
`/v1/chat/completions` — Ollama, LM Studio, llama.cpp. It cannot speak to a
Claude subscription, because a subscription is a CLI on a computer rather than
an HTTP endpoint, and a phone cannot shell out. This is the missing forty lines.
Nothing changes in the app but a preset.

**It costs the subscription, not a key.** There is no API key here and none is
wanted. Every request is `claude -p` on that machine, under whatever account
`claude` is logged in as, billed the way any other Claude Code use is. The
response carries `claude_cost_usd` so you can see what an answer cost.

**A token is required by default.** duckbench runs physics and can be left open
on a home network; this one spends somebody's quota, so anything that can reach
the port can spend it.

```sh
CLAUDEBRIDGE_TOKEN=$(openssl rand -hex 16) node tools/claudebridge.mjs
# claude bridge on http://0.0.0.0:8780/v1 — models: opus, sonnet, haiku
# token required
```

Then in Duck Studio: **Models → Claude, through my subscription**, put in the
machine's address and the token, and **Ask what models it has**.

| env | default | |
|---|---|---|
| `CLAUDEBRIDGE_PORT` | 8780 | |
| `CLAUDEBRIDGE_TOKEN` | — | required unless `--open` |
| `CLAUDEBRIDGE_MODELS` | `opus,sonnet,haiku` | what `/v1/models` lists |
| `CLAUDEBRIDGE_TIMEOUT` | 300 | seconds per request |

### Measured on a Raspberry Pi 5

Same app code, same prompts, three backends:

| | motion draft | training request |
|---|---|---|
| `gemma4:e4b-it-qat` (7.5B, local) | **766 s** | — |
| `qwen3.5:2b` (local, reasoning off) | — | **565 s** |
| Claude `sonnet` through this bridge | **8.8 s** | **26.5 s** |

The local models work — both produced valid, checkable drafts, which is the
point of the app checking everything afterwards. They are just very slow on a
board like this, and the bridge is the difference between drafting being
something you do and something you schedule.

### What it deliberately does not do

- **No tools.** `--allowed-tools ""`. A bridge that could read the filesystem
  because somebody asked it nicely would be a different and much worse program.
- **No streaming.** The app does not stream, and a bridge that pretended to
  would be inventing a protocol nobody reads.
- **No key handling.** If you want an API key instead of a subscription, point
  the app straight at the service — it already speaks that protocol.
