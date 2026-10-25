const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.join(__dirname, '..');

function fixture() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-style-'));
  const bin = path.join(tmp, 'bin');
  const home = path.join(tmp, 'home');
  fs.mkdirSync(bin); fs.mkdirSync(home);
  const cmd = {
    'kreadconfig6': `#!/bin/sh\nfile=""; group=""; key=""; while [ $# -gt 0 ]; do case "$1" in --file) file="$2"; shift 2;; --group) group="$2"; shift 2;; --key) key="$2"; shift 2;; *) shift;; esac; done\ncat "$STYLE_MOCK_DIR/$file-$group-$key" 2>/dev/null || :\n`,
    'kwriteconfig6': `#!/bin/sh\nfile=""; group=""; key=""; while [ $# -gt 0 ]; do case "$1" in --file) file="$2"; shift 2;; --group) group="$2"; shift 2;; --key) key="$2"; shift 2;; --notify) shift;; *) value="$1"; shift;; esac; done\nprintf '%s' "$value" > "$STYLE_MOCK_DIR/$file-$group-$key"\n`,
    'plasma-apply-lookandfeel': `#!/bin/sh\nprintf %s "$2" > "$STYLE_MOCK_DIR/applied"\nprintf %s "$2" > "$STYLE_MOCK_DIR/kdeglobals-KDE-LookAndFeelPackage"\n`,
    'qdbus6': `#!/bin/sh\nprintf '%s ' "$@" > "$STYLE_MOCK_DIR/qdbus-call"\n`
  };
  for (const [name, script] of Object.entries(cmd)) {
    fs.writeFileSync(path.join(bin, name), script, { mode: 0o755 });
  }
  function set(key, value) { fs.writeFileSync(path.join(tmp, key), value); }
  function get(key) { return fs.readFileSync(path.join(tmp, key), 'utf8'); }
  set('kdeglobals-KDE-AutomaticLookAndFeel', 'true');
  set('kdeglobals-KDE-LookAndFeelPackage', 'org.ipad.dark');
  const env = {...process.env, PATH:bin+':'+process.env.PATH, HOME:home, STYLE_MOCK_DIR:tmp};
  function run(style) { return cp.spawnSync('bash', [path.join(root, 'bin/shell-style'), style], {env, encoding:'utf8', timeout:12000}); }
  return {tmp, set, get, run};
}

test('Pixel changes both light/dark KDE packages, updates plasmoids, keeps automatic mode', t => {
  const f = fixture(); t.after(() => fs.rmSync(f.tmp, {recursive:true, force:true}));
  let result = f.run('pixel');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.get('tabletrc-Appearance-shellStyle'), 'pixel');
  assert.equal(f.get('kdeglobals-KDE-DefaultLightLookAndFeel'), 'org.tabletshell.pixel.light');
  assert.equal(f.get('kdeglobals-KDE-DefaultDarkLookAndFeel'), 'org.tabletshell.pixel.dark');
  assert.equal(f.get('applied'), 'org.tabletshell.pixel.dark');
  assert.equal(f.get('kdeglobals-KDE-AutomaticLookAndFeel'), 'true');
  assert.match(f.get('qdbus-call'), /writeConfig\('shellStyle', 'pixel'\)/);
  assert.equal(f.run('status').stdout.trim(), 'pixel');
  result = f.run('apple');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(f.get('applied'), 'org.ipad.dark');
  assert.equal(f.get('tabletrc-Appearance-shellStyle'), 'apple');
  assert.equal(f.get('kdeglobals-KDE-AutomaticLookAndFeel'), 'true');
});

test('invalid shell style does not alter preferences', t => {
  const f = fixture(); t.after(() => fs.rmSync(f.tmp, {recursive:true, force:true}));
  assert.equal(f.run('pixelz').status, 2);
  assert.equal(f.run('status').stdout.trim(), 'apple');
  assert.equal(fs.existsSync(path.join(f.tmp, 'tabletrc-Appearance-shellStyle')), false);
});

test('material theme available in whole shell; locks, widgets and keyboard bind to the same preference', () => {
  const read = p => fs.readFileSync(path.join(root, p), 'utf8');
  for (const component of [
    'src/tablet-settings/qml/Main.qml', 'src/tabletshell/control.qml',
    'src/tablet-keyboard/qml/Main.qml', 'src/tablet-greeter/LockSurface.qml',
    'shell/plasmoids/org.ipad.homescreen/contents/ui/main.qml',
    'shell/plasmoids/org.ipad.dashboard/contents/ui/main.qml'
  ]) assert.match(read(component), /pixel/, component);
  assert.match(read('src/common/ui-style.h'), /QFileSystemWatcher/);
  assert.match(read('bin/lockscreen-sync'), /"shellStyle"/);
  assert.match(read('systemd/lockscreen-sync.path'), /PathChanged=%h\/\.config\/tabletrc/);
  for (const mode of ['dark','light']) {
    assert.match(read(`shell/look-and-feel/org.tabletshell.pixel.${mode}/contents/defaults`), /Theme=TabletPixel/);
  }
});
