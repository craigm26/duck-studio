// The Dock routine on a duckbench, in process, with the steps and numbers in `DockRoutine.steps`.
//
// WHY THIS EXISTS. `MicroDock.swift` states what the routine did on the bench before the app was
// allowed to offer it: that a seated duck handed from Pollen's sit-stand to the MicroDock scoot
// network actually scoots on this plant. This is the run behind those numbers, kept so they can be
// reproduced rather than believed.
//
//   node scripts/measure_dock_routine.mjs
//   PARAMS=<dir of canonical .bin> node scripts/measure_dock_routine.mjs   # the phone's engine
//
// DUCKBENCH (default ~/projects/duckbench) is the bench checkout; the scoot networks and the
// sit-stand come from this repository's DuckStudio/Resources, the same files the app bundles.
// Without PARAMS the networks run on onnxruntime, as a desk bench runs them. With PARAMS (a folder
// holding `<name>.bin` canonical parameter bytes, from duckbench's sim/dumpparams, for
// scoot_dock, scoot_undock and sitstand-v6) they run on policyforward.mjs, as the phone runs them.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const RES = path.join(HERE, '..', 'DuckStudio', 'Resources');
const SIM = path.join(process.env.DUCKBENCH || path.join(os.homedir(), 'projects', 'duckbench'), 'sim');
const PARAMS = process.env.PARAMS || null;

async function phoneEngineBench() {
  const { default: load } = await import(path.join(SIM, 'node_modules/mujoco/mujoco.js'));
  const { makeBench } = await import(path.join(SIM, 'duckbench-core.mjs'));
  const { makeForwardSession, policyByteProblem } = await import(path.join(SIM, 'policyforward.mjs'));
  const scratch = new Map();
  const shipped = new Map(fs.readdirSync(SIM).filter(f => f.endsWith('.onnx')).map(f => [f, f]));
  return makeBench({
    sceneName: 'scene.mjb', mujoco: await load(),
    readAsset: name => shipped.has(name)
      ? fs.readFileSync(path.join(SIM, 'params', name.replace(/\.onnx$/, '.bin')))
      : fs.readFileSync(path.join(SIM, name)),
    listPolicies: () => [...shipped.keys(), ...scratch.keys()],
    sha256: b => createHash('sha256').update(b).digest('hex'), cores: 1,
    makeSession(bytes, name) {
      const problem = policyByteProblem(bytes);
      if (problem) throw new Error(`${name}: ${problem}`);
      return makeForwardSession(bytes, name);
    },
    scratch: { has: n => scratch.has(n), get: n => scratch.get(n), set: (n, b) => scratch.set(n, b),
               delete: n => scratch.delete(n) },
    host: { kind: 'phone', device: 'desk copy of the phone shell', engine: 'policyforward.mjs' },
  });
}

const bench = PARAMS ? await phoneEngineBench()
                     : await (await import(path.join(SIM, 'duckbench-node.mjs'))).nodeBench();
const H = async (p, b = {}) => {
  const r = await bench.handle(new URL('http://bench' + p), b);
  if (r?.error) throw new Error(`${p}: ${r.error}`);
  return r;
};
const upload = async (file, name) => (await H('/upload', {
  onnx: fs.readFileSync(PARAMS ? path.join(PARAMS, `${name}.bin`) : path.join(RES, file)).toString('base64'),
  name,
})).policy;

const SIT = await upload('alpha_sitstand.onnx', 'sitstand-v6');
const BACK = await upload('scoot_dock.onnx', 'scoot_dock');
const OUT = await upload('scoot_undock.onnx', 'scoot_undock');

// DockRoutine.steps, transcribed: [phase, network, command[0], seconds, until metres along].
const STEPS = [
  ['sit', SIT, 1, 4.0, null], ['handOver', BACK, 0, 0.5, null], ['scootBack', BACK, -0.05, 4.0, null],
  ['rest', BACK, 0, 3.0, null], ['scootOut', OUT, 0.05, 10.0, 0.070], ['still', OUT, 0, 0.5, null],
  ['stand', SIT, 0, 3.5, null],
];
const yaw = q => Math.atan2(2 * (q[0] * q[3] + q[1] * q[2]), 1 - 2 * (q[2] * q[2] + q[3] * q[3]));
const along = (a, b, h) => (b.position[0] - a.position[0]) * Math.cos(h) + (b.position[1] - a.position[1]) * Math.sin(h);

let s = await H('/reset', {});
let upright = true;
const report = { engine: PARAMS ? 'policyforward.mjs' : 'onnxruntime-node', phases: {} };
for (const [phase, policy, vx, seconds, until] of STEPS) {
  s = await H('/policy', { policy });
  const from = s, heading = yaw(s.quaternion);
  for (let left = seconds; left > 1e-9;) {
    const hold = Math.min(until ? 0.1 : 2, left);
    s = await H('/intent', { vx, hold });
    left -= hold;
    upright = upright && s.upright;
    if (until && along(from, s, heading) >= until) break;
  }
  report.phases[phase] = { mm: +(along(from, s, heading) * 1000).toFixed(1), seconds: +(s.t - from.t).toFixed(2),
                           trunk_mm: +(s.height * 1000).toFixed(1) };
}
report.upright_throughout = upright;
console.log(JSON.stringify(report, null, 1));
