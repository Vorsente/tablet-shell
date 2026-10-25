const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const os = require('node:os');
const path = require('node:path');
const root = path.join(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');

// This checks the update-specific safety contract without pretending to compile Qt on CI.
test('keyboard build is isolated, atomic, and update may reuse only an installed executable', () => {
  const build = read('build.sh');
  const kb = read('scripts/build-keyboard.sh');
  const up = read('update.sh');
  assert.match(build, /bash \.\/scripts\/build-target\.sh "\$name"/);
  assert.match(read('scripts/build-target.sh'), /bash \.\/scripts\/build-keyboard\.sh/);
  assert.match(build, /TABLET_SHELL_SKIP_FAILED_BUILDS/);
  assert.match(build, /-x "\$PREFIX\/\$1\/\$1"/);
  assert.match(build, /\.keyboard-reuse-installed/);
  assert.match(up, /TABLET_SHELL_EXCLUDE_INPUT_LOCK=1 bash \.\/build\.sh/);
  assert.match(up, /--keep-keyboard/);
  assert.match(up, /Keyboard \+ lock\/login screen: excluded/);
  assert.match(up, /--require-keyboard/);
  assert.match(up, /PARTIAL UPDATE/);
  assert.match(kb, /Qt6WaylandClient/);
  assert.match(kb, /QTINCLUDE=\$\(pkg-config --variable=includedir Qt6WaylandClient\)/);
  assert.match(kb, /tablet-keyboard\.new/);
  assert.match(kb, /mv -f "\$K\/tablet-keyboard\.new" "\$OUT\/tablet-keyboard"/);
});

test('installer preserves old keyboard executable, QML, sounds and session when build skipped', () => {
  const install = read('install.sh');
  assert.match(install, /! protected tablet-keyboard && ! skipped tablet-keyboard/);
  assert.match(install, /! protected "\$component" && ! skipped "\$component"/);
  assert.match(install, /! protected sounds-keyboard && ! skipped sounds-keyboard/);
  assert.doesNotMatch(install, /pkill .*tablet-keyboard/);
  assert.match(install, /Клавиатура обновлена на диске/);
  assert.match(install, /--reuse-component/);
  for (const script of ['build.sh','install.sh','update.sh','scripts/build-keyboard.sh']) {
    const check = cp.spawnSync('bash',['-n',path.join(root,script)],{encoding:'utf8'});
    assert.equal(check.status, 0, `${script}: ${check.stderr}`);
  }
});

test('manifest removes only previously installed unchanged files; unknown and modified files survive', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(),'tablet-manifest-'));
  try {
    const src=path.join(tmp,'repo');
    const home=path.join(tmp,'home');
    const scripts=path.join(src,'bin');
    const bin=path.join(home,'.local/bin');
    fs.mkdirSync(scripts,{recursive:true}); fs.mkdirSync(bin,{recursive:true});
    fs.writeFileSync(path.join(src,'install.sh'),'#!/bin/bash\n');
    const own=path.join(scripts,'owned');
    const changed=path.join(scripts,'customized');
    const unknown=path.join(bin,'other-app');
    fs.writeFileSync(own,'owned v1'); fs.writeFileSync(changed,'original');
    fs.copyFileSync(own,path.join(bin,'owned'));
    fs.copyFileSync(changed,path.join(bin,'customized'));
    fs.writeFileSync(unknown,'my data');
    const python = String.raw`
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('managed',sys.argv[1]); mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
mod.reconcile(pathlib.Path(sys.argv[2]),pathlib.Path(sys.argv[3]))
`;
    function reconcile() {
      const v=cp.spawnSync('python3',['-c',python,path.join(root,'scripts/managed-files.py'),src,home],{encoding:'utf8'});
      assert.equal(v.status,0,v.stderr||v.stdout);
    }
    reconcile();
    fs.unlinkSync(own); fs.unlinkSync(changed);
    fs.writeFileSync(path.join(bin,'customized'),'modified by user');
    reconcile();
    assert.equal(fs.existsSync(path.join(bin,'owned')),false);
    assert.equal(fs.readFileSync(path.join(bin,'customized'),'utf8'),'modified by user');
    assert.equal(fs.readFileSync(unknown,'utf8'),'my data');
  } finally { fs.rmSync(tmp,{recursive:true,force:true}); }
});

test('reuse-keyboard manifest never classifies installed old keyboard as obsolete', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(),'tablet-manifest-kb-'));
  try {
    const src=path.join(tmp,'repo');
    const home=path.join(tmp,'home');
    const sourceFile=path.join(src,'src/tablet-keyboard/qml/Main.qml');
    const installed=path.join(home,'.local/share/tablet-keyboard/qml/Main.qml');
    fs.mkdirSync(path.dirname(sourceFile),{recursive:true});
    fs.mkdirSync(path.dirname(installed),{recursive:true});
    fs.writeFileSync(path.join(src,'install.sh'),'');
    fs.writeFileSync(sourceFile,'old qml'); fs.writeFileSync(installed,'old qml');
    const python=String.raw`
import importlib.util, pathlib, sys
spec=importlib.util.spec_from_file_location('managed',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.reconcile(pathlib.Path(sys.argv[2]),pathlib.Path(sys.argv[3]),reuse_keyboard=(sys.argv[4]=='true'))
`;
    const run=(reuse)=>cp.spawnSync('python3',['-c',python,path.join(root,'scripts/managed-files.py'),src,home,String(reuse)],{encoding:'utf8'});
    assert.equal(run(false).status,0);
    fs.unlinkSync(sourceFile);
    assert.equal(run(true).status,0);
    assert.equal(fs.readFileSync(installed,'utf8'),'old qml');
  } finally { fs.rmSync(tmp,{recursive:true,force:true}); }
});


test('scripts remain callable after ZIP extraction loses executable permissions', () => {
  const build = read('build.sh');
  const install = read('install.sh');
  assert.match(build, /bash \.\/scripts\/build-target\.sh "\$name"/);
  assert.match(read('scripts/build-target.sh'), /bash \.\/scripts\/build-keyboard\.sh/);
  assert.match(install, /bash \.\/scripts\/install-lazyvim\.sh/);
  assert.match(install, /TABLET_SHELL_EXCLUDE_INPUT_LOCK=/);
  assert.match(install, /bash scripts\/themes\.sh/);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tablet-execbit-'));
  try {
    const file = path.join(dir, 'no-execute.sh');
    fs.writeFileSync(file, '#!/bin/bash\necho keyboard-builder-ran\n');
    fs.chmodSync(file, 0o644);
    const direct = cp.spawnSync(file, [], {encoding:'utf8'});
    assert.notEqual(direct.status, 0);
    const viaBash = cp.spawnSync('bash', [file], {encoding:'utf8'});
    assert.equal(viaBash.status, 0, viaBash.stderr);
    assert.match(viaBash.stdout, /keyboard-builder-ran/);
  } finally { fs.rmSync(dir, {recursive:true,force:true}); }
});
