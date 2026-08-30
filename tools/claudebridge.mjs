#!/usr/bin/env node
// claudebridge.mjs — put Claude behind an OpenAI-compatible endpoint, using the
// Claude Code subscription already signed in on this machine.
//
// WHY THIS EXISTS. Duck Studio can draft against anything that speaks
// /v1/chat/completions: Ollama, LM Studio, llama.cpp. It cannot speak to a
// Claude subscription, because a subscription is a CLI on a computer, not an
// HTTP endpoint — and a phone cannot shell out. So this is the missing forty
// lines: a server on the machine that IS signed in, answering the same protocol
// the app already speaks. Nothing changes in the app but a preset.
//
// IT COSTS THE SUBSCRIPTION, NOT A KEY. There is no API key here and none is
// wanted. Every request is `claude -p` on this machine, under whatever account
// `claude` is logged in as, and it is billed the way any other Claude Code use
// is.
//
// A TOKEN IS REQUIRED BY DEFAULT, and that is not paranoia. duckbench runs
// physics and can be left open on a home network; this one spends somebody's
// quota, so anything that can reach the port can spend it. Set
// CLAUDEBRIDGE_TOKEN, or pass --open if you genuinely mean to leave it
// unguarded.
//
//   CLAUDEBRIDGE_TOKEN=$(openssl rand -hex 16) node claudebridge.mjs
//
// Env:
//   CLAUDEBRIDGE_PORT    default 8780
//   CLAUDEBRIDGE_TOKEN   bearer token the app must send
//   CLAUDEBRIDGE_MODELS  comma-separated, default "opus,sonnet,haiku"
//   CLAUDEBRIDGE_TIMEOUT seconds per request, default 300
import http from 'node:http';
import { spawn } from 'node:child_process';

const PORT = +(process.env.CLAUDEBRIDGE_PORT || 8780);
const TOKEN = process.env.CLAUDEBRIDGE_TOKEN || '';
const OPEN = process.argv.includes('--open');
const MODELS = (process.env.CLAUDEBRIDGE_MODELS || 'opus,sonnet,haiku')
  .split(',').map(s => s.trim()).filter(Boolean);
const TIMEOUT = +(process.env.CLAUDEBRIDGE_TIMEOUT || 300) * 1000;

if (!TOKEN && !OPEN) {
  console.error('Refusing to start without CLAUDEBRIDGE_TOKEN.');
  console.error('Anything that can reach this port can spend your Claude quota.');
  console.error('  CLAUDEBRIDGE_TOKEN=$(openssl rand -hex 16) node claudebridge.mjs');
  console.error('Or pass --open if you really mean to.');
  process.exit(1);
}

/**
 * Run one prompt through the CLI.
 *
 * THE PROMPT GOES ON STDIN, NOT IN ARGV. A drafting prompt carries braces,
 * quotes and newlines, and an argument list is the wrong place for any of them
 * — the first version put it in argv and a flag swallowed it.
 *
 * Tools are off. This is a text-in, text-out service; a bridge that could read
 * the filesystem because somebody asked it nicely would be a different and much
 * worse program.
 */
function ask({ model, prompt, system }) {
  return new Promise((resolve, reject) => {
    const args = ['-p', '--output-format', 'json', '--allowed-tools', ''];
    if (model) args.push('--model', model);
    if (system) args.push('--append-system-prompt', system);
    const child = spawn('claude', args, { stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '', err = '';
    const timer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error('timed out')); },
                             TIMEOUT);
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { err += d; });
    child.on('error', e => { clearTimeout(timer); reject(e); });
    child.on('close', code => {
      clearTimeout(timer);
      if (code !== 0) return reject(new Error(err.trim() || `claude exited ${code}`));
      try {
        const parsed = JSON.parse(out);
        if (parsed.is_error) return reject(new Error(parsed.result || 'claude reported an error'));
        resolve(parsed);
      } catch {
        reject(new Error('claude did not answer with JSON: ' + out.slice(0, 200)));
      }
    });
    child.stdin.end(prompt);
  });
}

const json = (res, code, body) => {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
};

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (TOKEN) {
    const sent = (req.headers.authorization || '').replace(/^Bearer /, '');
    if (sent !== TOKEN) return json(res, 401, { error: { message: 'bad or missing token' } });
  }

  if (url.pathname === '/v1/models') {
    return json(res, 200, {
      object: 'list',
      data: MODELS.map(id => ({ id, object: 'model', owned_by: 'anthropic' })),
    });
  }

  if (url.pathname === '/v1/chat/completions' && req.method === 'POST') {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    let body;
    try { body = JSON.parse(raw); } catch { return json(res, 400, { error: { message: 'not JSON' } }); }

    const messages = Array.isArray(body.messages) ? body.messages : [];
    // The system message becomes the system prompt; everything else is the
    // turn. Keeping them apart matters: a system prompt appended to the user's
    // text is a system prompt the model can be argued out of.
    const system = messages.filter(m => m.role === 'system').map(m => m.content).join('\n\n');
    const prompt = messages.filter(m => m.role !== 'system')
                           .map(m => m.content).join('\n\n');
    if (!prompt.trim()) return json(res, 400, { error: { message: 'no prompt in messages' } });

    const model = MODELS.includes(body.model) ? body.model : MODELS[0];
    try {
      const answer = await ask({ model, prompt, system });
      const usage = answer.usage || {};
      return json(res, 200, {
        id: 'chatcmpl-' + (answer.session_id || 'claude'),
        object: 'chat.completion',
        created: Math.floor(Date.now() / 1000),
        model,
        choices: [{
          index: 0,
          message: { role: 'assistant', content: answer.result ?? '' },
          finish_reason: 'stop',
        }],
        usage: {
          prompt_tokens: usage.input_tokens ?? 0,
          completion_tokens: usage.output_tokens ?? 0,
          total_tokens: (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0),
        },
        // Not part of the protocol, and useful: what that answer cost.
        claude_cost_usd: answer.total_cost_usd,
        claude_duration_ms: answer.duration_ms,
      });
    } catch (e) {
      return json(res, 502, { error: { message: String(e.message || e) } });
    }
  }

  json(res, 404, { error: { message: 'try /v1/models or /v1/chat/completions' } });
}).listen(PORT, '0.0.0.0', () => {
  console.log(`claude bridge on http://0.0.0.0:${PORT}/v1 — models: ${MODELS.join(', ')}`);
  console.log(TOKEN ? 'token required' : 'OPEN — anything on this network can spend your quota');
});
