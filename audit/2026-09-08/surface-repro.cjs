// Safe reproductions: UI controller substitutes and shell-command substitutes only.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
let count = 0;
function check(condition, label) {
  if (!condition) throw new Error(label);
  console.log(`ok ${++count} - ${label}`);
}
for (const version of [8, 9]) {
  const patch = fs.readFileSync(path.join(root, `pve-manager/js/pvemanagerlib.js.${version}.patch`), 'utf8');
  const code = patch.split('\n').filter(l => l.startsWith('+') && !l.startsWith('+++') || l.startsWith(' ')).map(l => l.slice(1)).join('\n');
  const start = code.indexOf('function (f, newVal, oldVal)');
  if (start < 0) throw new Error('controller function boundary missing');
  const brace = code.indexOf('{', start);
  let depth = 1, end = brace + 1;
  for (; end < code.length && depth; end++) {
    if (code[end] === '{') depth++;
    if (code[end] === '}') depth--;
  }
  if (depth) throw new Error('controller function boundary unbalanced');
  const callback = vm.runInNewContext(`(${code.slice(start, end)})`);
  const refs = Object.fromEntries([...code.matchAll(/reference:\s*'([^']+)'/g)].map(m => [m[1], {setValue() {}}]));
  const context = { getViewModel() { return {set() {}}; }, lookupReference(name) { return refs[name]; } };
  let error;
  try { callback.call(context, null, 'comstar', 'truenas'); } catch (e) { error = e; }
  check(error && /setValue/.test(error.message), `BUG: PVE ${version} provider switch hits missing API-key reference`);
}
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'truenas-deploy-audit-'));
try {
  const log = path.join(work, 'commands.log');
  const commands = ['dpkg-query','cp','mv','rm','rsync','systemctl','apt','patch','sed','mkdir'];
  for (const name of commands) {
    const content = name === 'dpkg-query'
      ? '#!/bin/sh\necho "proxmox-ve 9.0"\n'
      : '#!/bin/sh\nprintf "%s\\n" "' + name + ' $*" >> "$AUDIT_COMMAND_LOG"\n' + (['cp','mv','rsync','patch'].includes(name) ? 'exit 7\n' : 'exit 0\n');
    fs.writeFileSync(path.join(work, name), content, {mode: 0o755});
  }
  const opts = {cwd: root, env: {...process.env, PATH: `${work}:/usr/bin:/bin`, AUDIT_COMMAND_LOG: log}, encoding: 'utf8', timeout: 3000};
  const run = spawnSync('/bin/bash', ['deploy.sh'], opts);
  const trace = fs.readFileSync(log, 'utf8');
  check(run.status === 0 && /systemctl restart corosync pve-cluster/.test(trace), 'BUG: failed deploy copies still produce success and cluster restart');
  const unknown = spawnSync('/bin/bash', ['deploy.sh','--audit-unknown-option'], {...opts, timeout: 300});
  check(unknown.error && unknown.error.code === 'ETIMEDOUT', 'BUG: unknown deployment argument loops until external timeout');
} finally {
  fs.rmSync(work, {recursive: true, force: true});
}
console.log(`1..${count}`);
