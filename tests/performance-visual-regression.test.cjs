const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = r => fs.readFileSync(path.join(root, r), 'utf8');

test('home dock spacing uses actual style-specific dock height without overwriting custom spacing', () => {
  const qml = read('shell/plasmoids/org.ipad.homescreen/contents/ui/main.qml');
  assert.match(qml, /pageDotsClearance/);
  assert.match(qml, /pixel \? 80 : 72/);
  assert.match(qml,/anchors\.bottomMargin: root\.dockReserve/);
  assert.match(read('shell/plasmoids/org.ipad.homescreen/contents/config/main.xml'), /name="dockSpace"[^\n]*<default>64<\/default>/);
});
test('animated weather is an opt-in effect; avoid double full screen GPU targets', () => {
  const fx = read('shell/plasmoids/org.ipad.homescreen/contents/ui/WeatherEffects.qml');
  const home = read('shell/plasmoids/org.ipad.homescreen/contents/ui/main.qml');
  assert.doesNotMatch(fx,/readonly property real scale:/); // shadows built-in Item.scale and breaks QML
  assert.match(fx,/mipmap: false/);
  assert.match(fx,/layer\.enabled: false/);
  assert.match(home,/configuration\.weatherAnimation \? "animated" : "static"/);
  assert.match(read('shell/plasmoids/org.ipad.homescreen/contents/config/main.xml'),/name="weatherAnimation"[^\n]*<default>false<\/default>/);
});
test('transition readiness no longer hard-waits for timeout on PC/tablet switches',()=>{
  const qml = read('src/tabletshell/ModeTransition.qml');
  assert.match(qml,/isReady = to === "reading"/);
  assert.match(qml,/run\(Math\.max\(t, holdEnd\), total\)/);
  assert.match(qml,/transform: \[/);
  assert.doesNotMatch(qml,/transform: Matrix4x4/);
});
test('panel spans screen and stays centred; desktop scaling opt-in on slower GPUs',()=>{
  const panels=read('shell/tablet-mode/morph-panels.js');
  assert.match(panels,/bar\.lengthMode = "fill"/);
  assert.match(panels,/bar\.alignment = "center"/);
  assert.match(panels,/bar\.offset = 0/);
  assert.match(read('src/tabletd/tabletd.cpp'),/"changeDisplayScale", false/);
});
test('Pixel icon pack is real, has Material glyph assets and does not claim ownership of other apps',()=>{
  const icons=path.join(root,'shell/icons/TabletPixel');
  assert.match(fs.readFileSync(path.join(icons,'index.theme'),'utf8'),/Inherits=Colloid,Colloid-Dark,Colloid-Light,breeze/);
  const v=fs.readdirSync(path.join(icons,'scalable/actions')).filter(f=>f.endsWith('.svg'));
  assert.ok(v.length>=10);
  const svg=fs.readFileSync(path.join(icons,'scalable/actions/notifications-symbolic.svg'),'utf8');
  assert.match(svg, /viewBox="0 0 48 48"/);
  assert.match(read('bin/shell-style'), /Icons --key Theme --notify "TabletPixel\$\{mode\^\}"/);
  assert.match(read('scripts/managed-files.py'), /\('shell\/icons', '\.local\/share\/icons'\)/);
});
test('coding prompt offers LazyVim with two concise sentences, alongside typewriter actions',()=>{
  const src=read('src/tabletd/tabletd.cpp');
  assert.match(src,/action == QLatin1String\("coding"\)/);
  assert.match(src,/Клавиатура подключена\./);
  assert.match(src,/Можно писать тексты или открыть LazyVim для программирования\./);
  assert.match(read('bin/coding-mode'),/Режим кодинга включён\. Открывается LazyVim\./);
});
test('updater has terminal stages and ABI keyed compiled cache, while preserving previous keyboard',()=>{
  const build=read('build.sh');
  assert.match(build,/CACHE_KEY=/);
  assert.match(build,/Qt6WaylandClient/);
  assert.match(build,/\.keyboard-reuse-installed/);
  const update=read('update.sh');
  assert.match(update,/stage 1/);
  assert.match(update,/stage 4/);
  assert.match(update, /TABLET_SHELL_SKIP_FAILED_BUILDS="\$SKIP_FAILED_BUILDS"/);
  for(const f of ['build.sh','update.sh','bin/coding-mode','bin/lockscreen-sync','install.sh']) {
    const proc=cp.spawnSync('bash',['-n',path.join(root,f)]);
    assert.equal(proc.status,0,`${f}: ${proc.stderr}`);
  }
});
test('lockscreen QML includes both looks and is synced without forcing a greeter login-manager replacement',()=>{
  assert.match(read('src/tablet-greeter/LockSurface.qml'),/readonly property bool pixel:/);
  assert.match(read('bin/lockscreen-sync'),/"shellStyle": "%s"/);
  assert.match(read('install.sh'),/\[ -n "\$GREETER_UPDATE" \]/);
});
