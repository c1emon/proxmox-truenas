const fs = require('node:fs');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
let passed = 0;
const command = (exe, args, options = {}) => {
  const r = cp.spawnSync(exe, args, { encoding: 'utf8', timeout: 15000, ...options });
  assert.ifError(r.error); assert.equal(r.signal, null);
  assert.equal(r.status, 0, `${exe}: ${r.stdout}\n${r.stderr}`); return r;
};
const write = (p, s) => { fs.mkdirSync(require('node:path').dirname(p), {recursive:true}); fs.writeFileSync(p,s,{mode:0o755}); };
for (const [v,m,s] of [[8,'8.4.14','8.3.7'],[9,'9.2.10','9.1.10']]) {
  const base=`/validation${v}`; fs.mkdirSync(base);
  const original=`${base}/original`; fs.mkdirSync(original);
  for (const [pkg,version] of [['pve-manager',m],['libpve-storage-perl',s]]) command('dpkg-deb',['-x',`/packages/${pkg}_${version}_all.deb`,original]);
  const src=`${base}/source`; fs.cpSync('/work',src,{recursive:true});
  const target=`${base}/target`; fs.cpSync(original,target,{recursive:true});
  const rel=['perl5/PVE/Storage/ZFSPlugin.pm','pve-manager/js/pvemanagerlib.js'];
  const originals=rel.map(r=>fs.readFileSync(`${original}/usr/share/${r}`));
  const expected=rel.map((r,i)=>{
    const f=`${base}/expected${i}`;fs.writeFileSync(f,originals[i]);
    const result=command('patch',['--batch','--forward','--ignore-whitespace',f],{input:fs.readFileSync(`${src}/${r}.${v}.patch`)});
    process.stdout.write(result.stdout);return fs.readFileSync(f);
  });
  fs.writeFileSync(`${src}/deploy.sh`,fs.readFileSync(`${src}/deploy.sh`,'utf8').replaceAll('/usr/share',`${target}/usr/share`));
  const bin=`${base}/bin`;fs.mkdirSync(bin);
  write(`${bin}/dpkg-query`,`#!/bin/sh\ncase "$*" in *pve-manager*) echo '${m}';; *libpve-storage-perl*) echo '${s}';; *) exit 1;; esac\n`);
  write(`${bin}/systemctl`, '#!/bin/sh\nprintf "%s\\n" "$*" >> "$SERVICE_LOG"\n[ "$FAIL_SERVICE" != 1 ]\n');
  write(`${bin}/sed`, '#!/bin/sh\n[ "$FAIL_SED" = 1 ] && exit 73\nexec /bin/sed "$@"\n');
  write(`${bin}/apt`, `#!/bin/sh\n[ "$*" = 'reinstall pve-manager libpve-storage-perl' ] || exit 74\ncp '${original}/usr/share/${rel[0]}' '${target}/usr/share/${rel[0]}' || exit\ncp '${original}/usr/share/${rel[1]}' '${target}/usr/share/${rel[1]}'\n`);
  const log=`${base}/services.log`;
  const run=(args,extra={})=>{
    fs.rmSync(log,{force:true});
    const r=cp.spawnSync('/bin/bash',[`${src}/deploy.sh`,...args],{cwd:'/tmp',encoding:'utf8',timeout:15000,env:{...process.env,PATH:`${bin}:/usr/bin:/bin`,SERVICE_LOG:log,...extra}});
    assert.ifError(r.error);assert.equal(r.signal,null);return r;
  };
  const success=(r)=>{assert.equal(r.status,0,r.stdout+r.stderr);assert.match(r.stdout,/Deployment completed/);assert.equal(fs.readFileSync(log,'utf8'),'restart corosync pve-cluster pvedaemon pvestatd pveproxy\n');};
  const check=(buffers)=>rel.forEach((r,i)=>assert.deepEqual(fs.readFileSync(`${target}/usr/share/${r}`),buffers[i]));
  const pass=(name)=>{passed++;console.log(`PASS PVE ${v}: ${name}`);};
  // Verify first installation matches patches applied to real package files.
  success(run(['-p']));check(expected);pass('first Patch install from real package files');
  // Verify repeat installation reuses the original backups without double patching.
  success(run(['-p']));check(expected);pass('repeat Patch install from retained originals');
  // Verify switching to Native restores the original package files.
  success(run([]));check(originals);assert(fs.existsSync(`${target}/usr/share/perl5/PVE/Storage/Custom/TrueNASPlugin.pm`));pass('Patch to Native restores originals');
  // Verify both reinstall modes ignore stale backups after package restoration.
  for (const args of [['-r','-p'],['-r']]) {
    rel.forEach(r=>fs.writeFileSync(`${target}/usr/share/${r}.orig`,'stale-backup\n'));
    success(run(args));check(args.includes('-p')?expected:originals);
    rel.forEach((r,i)=>args.includes('-p')?assert.deepEqual(fs.readFileSync(`${target}/usr/share/${r}.orig`),originals[i]):assert(!fs.existsSync(`${target}/usr/share/${r}.orig`)));
    pass(`${args.join(' ')} ignores stale backups after simulated reinstall`);
  }
  // Verify debug mode changes the installed logging level.
  success(run(['-d']));assert.match(fs.readFileSync(`${target}/usr/share/perl5/TrueNAS/Helpers.pm`,'utf8'),/log_level => 'debug'/);pass('debug logging enabled');
  // Verify a logging configuration failure stops before any restart.
  let r=run(['-d'],{FAIL_SED:'1'});assert.notEqual(r.status,0);assert.match(r.stderr,/enabling debug logging/);assert.doesNotMatch(r.stdout,/Deployment completed/);assert(!fs.existsSync(log));pass('sed failure stops before restart');
  // Verify a failed restart cannot produce a successful completion message.
  r=run([],{FAIL_SERVICE:'1'});assert.notEqual(r.status,0);assert.match(r.stderr,/restarting Proxmox services/);assert.doesNotMatch(r.stdout,/Deployment completed/);pass('restart failure is not reported as success');
  // Verify build output can be deployed with byte-identical results.
  rel.forEach((r,i)=>{fs.writeFileSync(`${src}/${r}.${v}.orig`,originals[i]);fs.writeFileSync(`${src}/${r}.${v}`,expected[i]);});
  command('/bin/bash',[`${src}/build.sh`],{cwd:'/tmp',env:{...process.env,PATH:`${bin}:/usr/bin:/bin`}});
  rel.forEach((r,i)=>{
    const f=`${base}/generated${i}`;fs.writeFileSync(f,originals[i]);
    command('patch',['--batch','--forward','--ignore-whitespace',f],{input:fs.readFileSync(`${src}/${r}.${v}.patch`)});
    assert.deepEqual(fs.readFileSync(f),expected[i]);
  });
  success(run(['-p']));check(expected);pass('build generates patches that deploy reproduces byte for byte');
}
console.log(`Package-backed scenarios: ${passed}/${passed} PASS`);
