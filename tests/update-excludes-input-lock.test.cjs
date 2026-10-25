const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const os = require('node:os');
const root = path.join(__dirname, '..');
const read = f => fs.readFileSync(path.join(root, f), 'utf8');

test('update-only excludes keyboard, lock QML and login screen from every install path', () => {
  const build = read('build.sh');
  const installer = read('install.sh');
  const updater = read('update.sh');
  const target = read('scripts/build-target.sh');
  for (const component of ['tablet-keyboard', 'tablet-greeter', 'sounds-keyboard']) {
    assert.match(build, new RegExp(`tablet-keyboard\\|tablet-greeter\\|sounds-keyboard`));
    assert.match(installer, new RegExp(`tablet-keyboard\\|tablet-greeter\\|sounds-keyboard`));
  }
  assert.match(updater, /TABLET_SHELL_EXCLUDE_INPUT_LOCK=1 bash \.\/build\.sh/);
  assert.match(installer, /--update-only\) UPDATE_ONLY=1; PROTECT_INPUT_LOCK=1; GREETER_UPDATE=;/);
  assert.match(installer, /if \[ -z "\$PROTECT_INPUT_LOCK" \]; then\s+if ! bash "\$BIN\/lockscreen-sync"/);
  assert.match(installer, /--reuse-component input-lock-assets/);
  assert.match(installer, /lockscreen-sync\.\*\|greeter-wallpaper\.\*/);
  assert.match(installer, /if ! protected tablet-keyboard && ! skipped tablet-keyboard/);
  assert.match(target, /TABLET_SHELL_EXCLUDE_INPUT_LOCK:-0/);
  assert.match(updater, /--no-greeter-update --skip-failed-builds/);
  assert.match(read('bin/tablet-shell-github-update'), /str\(source_dir \/ 'update.sh'\)/);
});

test('excluded parts are not compiled even when a complete-build cache could exist', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tablet-exclusion-build-'));
  try {
    const repo = path.join(tmp, 'repo');
    const prefix = path.join(tmp, 'installed');
    fs.mkdirSync(path.join(repo, 'scripts'), {recursive:true});
    fs.mkdirSync(path.join(repo, 'src'), {recursive:true});
    fs.mkdirSync(path.join(repo, 'i18n'), {recursive:true});
    fs.mkdirSync(path.join(repo, 'shell/plasmoids/org.ipad.homescreen/contents/ui/shaders'), {recursive:true});
    fs.copyFileSync(path.join(root, 'build.sh'), path.join(repo, 'build.sh'));
    fs.writeFileSync(path.join(repo, 'scripts/build-keyboard.sh'), '#!/bin/bash\nexit 99\n');
    fs.writeFileSync(path.join(repo, 'shell/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag'), '//fake');
    fs.writeFileSync(path.join(repo, 'src/something.cpp'), '//fake');
    fs.writeFileSync(path.join(repo, 'i18n/translation.py'), '#fake');
    fs.writeFileSync(path.join(repo, 'scripts/build-target.sh'), String.raw`#!/bin/bash
set -e
printf '%s\n' "$1" >> "$PREFIX/invocations"
case "$1" in
 translations) echo '{}' > build/en.json ;;
 shaders) echo 'shader' > build/weather.frag.qsb ;;
 sounds-shell) mkdir -p "build/sounds/shell"; echo wav > "build/sounds/shell/tone.wav" ;;
 tablet-keyboard|tablet-greeter) exit 99 ;;
 *) echo "program" > "build/$1" ;;
esac
`);
    fs.mkdirSync(prefix);
    const env = {...process.env, HOME:tmp, PREFIX:prefix, XDG_CACHE_HOME:path.join(tmp,'cache'), TABLET_SHELL_EXCLUDE_INPUT_LOCK:'1', TABLET_SHELL_SKIP_FAILED_BUILDS:'0'};
    const r=cp.spawnSync('bash', [path.join(repo,'build.sh')], {cwd:repo, env, encoding:'utf8'});
    assert.equal(r.status, 0, r.stderr || r.stdout);
    const invoked=fs.readFileSync(path.join(prefix,'invocations'), 'utf8');
    assert.doesNotMatch(invoked, /tablet-keyboard|tablet-greeter|sounds-keyboard/);
    assert.match(invoked, /tablet-settings/);
    assert.equal(fs.existsSync(path.join(repo, 'build/tablet-keyboard')), false);
    assert.equal(fs.existsSync(path.join(repo, 'build/tablet-greeter')), false);
  } finally { fs.rmSync(tmp, {recursive:true,force:true}); }
});

test('obsolete-file cleanup preserves excluded input/login files and lock sync helper', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tablet-exclusion-manifest-'));
  try {
    const repo=path.join(tmp,'repo'); const home=path.join(tmp,'home');
    fs.mkdirSync(repo); fs.mkdirSync(home);
    fs.writeFileSync(path.join(repo,'install.sh'),'');
    const cases=[
      ['src/tablet-keyboard/qml/Main.qml','.local/share/tablet-keyboard/qml/Main.qml'],
      ['src/tablet-greeter/LockSurface.qml','.local/share/tablet-greeter/LockSurface.qml'],
      ['bin/lockscreen-sync','.local/bin/lockscreen-sync'],
      ['applications/tablet-keyboard.desktop','.local/share/applications/tablet-keyboard.desktop'],
      ['systemd/lockscreen-sync.path','.config/systemd/user/lockscreen-sync.path'],
      ['system/greeter-launch.sh','.local/share/tablet-shell/system/greeter-launch.sh']
    ];
    for (const [src,rel] of cases) {
      fs.mkdirSync(path.dirname(path.join(repo,src)), {recursive:true});
      fs.mkdirSync(path.dirname(path.join(home,rel)), {recursive:true});
      fs.writeFileSync(path.join(repo,src),'original');
      fs.writeFileSync(path.join(home,rel),'original');
    }
    const python = String.raw`
import importlib.util, pathlib, sys
spec=importlib.util.spec_from_file_location('managed',sys.argv[1])
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
mod.reconcile(pathlib.Path(sys.argv[2]),pathlib.Path(sys.argv[3]),reuse_components=sys.argv[4:])
`;
    const exec = (...args) => cp.spawnSync('python3', ['-c',python,path.join(root,'scripts/managed-files.py'),repo,home,...args.filter(a => a!=='--reuse-component')], {encoding:'utf8'});
    let r=exec(); assert.equal(r.status,0,r.stderr || r.stdout);
    for (const [src] of cases) fs.rmSync(path.join(repo,src));
    r=exec('--reuse-component','tablet-keyboard','--reuse-component','tablet-greeter','--reuse-component','input-lock-assets');
    assert.equal(r.status,0,r.stderr || r.stdout);
    for (const [,rel] of cases) assert.equal(fs.readFileSync(path.join(home,rel),'utf8'),'original',rel);
  } finally { fs.rmSync(tmp, {recursive:true,force:true}); }
});
