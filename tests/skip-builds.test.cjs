const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const root = path.join(__dirname, '..');

function fixture() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tablet-partial-build-'));
  const project = path.join(tmp, 'tablet-shell');
  const home = path.join(tmp, 'home');
  const share = path.join(home, '.local/share');
  fs.mkdirSync(path.join(project, 'scripts'), {recursive:true});
  fs.mkdirSync(path.join(project, 'src'), {recursive:true});
  fs.mkdirSync(path.join(project, 'i18n'), {recursive:true});
  fs.mkdirSync(path.join(project,'shell/plasmoids/org.ipad.homescreen/contents/ui/shaders'), {recursive:true});
  fs.mkdirSync(path.join(share, 'tablet-settings'), {recursive:true});
  fs.mkdirSync(path.join(share, 'plasma/plasmoids/org.ipad.homescreen/contents/ui/shaders'), {recursive:true});
  fs.writeFileSync(path.join(share,'tablet-settings/tablet-settings'), 'previous-working-settings', {mode:0o755});
  fs.writeFileSync(path.join(share, 'plasma/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag.qsb'), 'previous shader');
  for (const name of ['build.sh', 'scripts/build-keyboard.sh', 'scripts/build-target.sh']) {
    fs.copyFileSync(path.join(root,name),path.join(project,name));
  }
  fs.writeFileSync(path.join(project,'shell/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag'), 'test shader');
  fs.writeFileSync(path.join(project,'scripts/build-target.sh'), `#!/bin/bash
set -e
name="$1"
mkdir -p build
case "$name" in
  tablet-settings|shaders) echo "synthetic compiler error in $name" >&2; exit 77 ;;
  sounds-shell) mkdir -p build/sounds/shell; printf audio > build/sounds/shell/p.wav ;;
  sounds-keyboard) mkdir -p build/sounds/keyboard; printf audio > build/sounds/keyboard/p.wav ;;
  translations) printf '{}' > build/en.json ;;
  *) printf 'built-%s' "$name" > "build/$name"; chmod +x "build/$name" ;;
esac
`);
  return {tmp, project, home, share};
}
function build(f, skips) {
  return cp.spawnSync('bash',['./build.sh'],{
    cwd:f.project,encoding:'utf8',timeout:30000,
    env:{...process.env,HOME:f.home,XDG_CACHE_HOME:path.join(f.tmp,'cache'),
         PREFIX:f.share,TABLET_SHELL_SKIP_FAILED_BUILDS:skips?'1':'0'}
  });
}
test('two failed components are skipped while successfully built binaries are still produced',()=>{
  const f=fixture();
  try {
    const p=build(f,true);
    assert.equal(p.status,0,p.stderr||p.stdout);
    assert.match(p.stderr,/PARTIAL BUILD/);
    for(const name of ['tablet-settings','shaders']) {
      assert.equal(fs.existsSync(path.join(f.project,'build/.skipped',name)),true);
    }
    assert.equal(fs.existsSync(path.join(f.project,'build/tablet-settings')),false);
    assert.equal(fs.existsSync(path.join(f.project,'build/weather.frag.qsb')),false);
    assert.equal(fs.readFileSync(path.join(f.project,'build/tabletshell'),'utf8'),'built-tabletshell');
    assert.equal(fs.readFileSync(path.join(f.share,'tablet-settings/tablet-settings'),'utf8'),'previous-working-settings');
    assert.equal(fs.existsSync(path.join(f.tmp,'cache/tablet-shell/compiled')),false);
  } finally {fs.rmSync(f.tmp,{recursive:true,force:true});}
});
test('strict build still reports failure rather than installing a partial result',()=>{
  const f=fixture();
  try {
    const p=build(f,false);
    assert.notEqual(p.status,0);
    assert.match(p.stderr,/FAILED — no safe installed fallback/);
  } finally {fs.rmSync(f.tmp,{recursive:true,force:true});}
});
test('missing previous executable cannot be treated as a successful skip',()=>{
  const f=fixture();
  try {
    fs.unlinkSync(path.join(f.share,'tablet-settings/tablet-settings'));
    const p=build(f,true);
    assert.notEqual(p.status,0);
    assert.match(p.stderr,/no safe installed fallback/);
  } finally {fs.rmSync(f.tmp,{recursive:true,force:true});}
});
test('cleanup preserves QML files of any skipped frontend instead of treating them as obsolete',()=>{
  const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'tablet-preserve-assets-'));
  try {
    const source=path.join(tmp,'source'), home=path.join(tmp,'home');
    const qml='src/tablet-settings/qml/Main.qml';
    const installed=path.join(home,'.local/share/tablet-settings/qml/Main.qml');
    fs.mkdirSync(path.dirname(path.join(source,qml)),{recursive:true});
    fs.mkdirSync(path.dirname(installed),{recursive:true});
    fs.writeFileSync(path.join(source,'install.sh'),'#!/bin/bash\n');
    fs.writeFileSync(path.join(source,qml),'old QML source');
    fs.writeFileSync(installed,'old QML source');
    const script=String.raw`
import importlib.util,pathlib,sys
spec=importlib.util.spec_from_file_location('managed',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.reconcile(pathlib.Path(sys.argv[2]),pathlib.Path(sys.argv[3]), reuse_components=['tablet-settings'] if len(sys.argv)>4 else [])
`;
    const p=cp.spawnSync('python3',['-c',script,path.join(root,'scripts/managed-files.py'),source,home],{encoding:'utf8'});
    assert.equal(p.status,0,p.stderr);
    fs.rmSync(path.join(source,qml));
    const p2=cp.spawnSync('python3',['-c',script,path.join(root,'scripts/managed-files.py'),source,home,'preserve'],{encoding:'utf8'});
    assert.equal(p2.status,0,p2.stderr);
    assert.equal(fs.readFileSync(installed,'utf8'),'old QML source');
  } finally {fs.rmSync(tmp,{recursive:true,force:true});}
});
