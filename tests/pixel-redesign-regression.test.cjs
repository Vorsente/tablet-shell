const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.join(__dirname, '..');
const read = f => fs.readFileSync(path.join(root, f),'utf8');

test('dots have distinct visual clearance above floating dock and do not force user custom reserve',()=>{
  const src = read('shell/plasmoids/org.ipad.homescreen/contents/ui/main.qml');
  assert.match(src,/pageDotsClearance: Kirigami\.Units\.smallSpacing \* 3/);
  assert.match(src,/anchors\.bottomMargin: root\.dockReserve \+ root\.pageDotsClearance/);
  assert.match(src,/dockSpace\) \|\| 0\)/);
});
test('Pixel widget content is a separate information hierarchy and Apple uses original widgets',()=>{
  const home = read('shell/plasmoids/org.ipad.homescreen/contents/ui/HomeWidget.qml');
  assert.match(home,/card\.home\.pixel \? pixelContent :/);
  assert.match(home,/visible: !card\.home\.pixel/);
  const px=read('shell/plasmoids/org.ipad.homescreen/contents/ui/PixelWidgetContent.qml');
  const dashboard=read('shell/plasmoids/org.ipad.dashboard/contents/ui/Widget.qml');
  assert.match(dashboard,/widget\.pal\.pixel \? widget\.title\.toUpperCase/);
  assert.match(dashboard,/Pixel dashboard cards/);
  for (const id of ['clockCard','weatherCard','batteryCard','calendarCard','glanceCard']) assert.ok(px.includes('id: '+id));
  assert.match(px,/\.linuxNews\[0\]\.title/);
  assert.match(px,/\.rates\.USD\.value/);
});
test('stylus picture and Krita icons use bundled images that work independently of theme',()=>{
  const qml = read('src/tabletshell/PenRing.qml');
  for (const n of ['krita','shot']) {
    assert.match(qml,new RegExp('icons/'+n+'\\.svg'));
    assert.ok(fs.existsSync(path.join(root,'src/tabletshell/icons',n+'.svg')));
    assert.match(read('src/tabletshell/icons/'+n+'.svg'),/viewBox=/);
  }
  assert.doesNotMatch(qml,/id: "magnifier"/);
});
test('Material dark and light have separate panel symbols and downloaded complete icon themes',()=>{
  for(const variant of ['Dark','Light']) {
    const base='shell/icons/TabletPixel'+variant;
    const theme=read(base+'/index.theme');
    assert.match(theme, new RegExp('Inherits=TabletPixel,Colloid-'+variant));
    assert.ok(fs.readdirSync(path.join(root,base,'scalable/actions')).length>=10);
  }
  assert.match(read('scripts/install-material-icons.sh'),/github.com\/vinceliuice\/Colloid-icon-theme/);
  assert.match(read('src/tabletd/icons.cpp'),/pixelTheme \? drawPixel\(src, sq\) : draw\(src, sq\)/);
  assert.match(read('systemd/app-icons.service'),/app-icons-refresh/);
  assert.match(read('install.sh'), /P \/apps\/scalable\/\*\*\*/);
  assert.match(read('update.sh'),/TABLET_SHELL_DOWNLOAD_ICONS=1 TABLET_SHELL_OFFLINE=/);
});
test('Style animations are independent lightweight layers and retained by installer',()=>{
  assert.match(read('bin/shell-style'),/theme-transition/);
  const animation =read('src/tabletshell/theme-transition.qml');
  // the curtain holds until shell-style is done, blocks taps while covered and always opens
  assert.match(animation,/tablet-style-ready/);
  assert.match(animation,/interval: 30000/);
  assert.match(read('bin/shell-style'),/tablet-style-covered/);
  assert.match(read('bin/shell-style'),/trap 'echo 1 > "\$rt\/tablet-style-ready"' EXIT/);
  assert.match(animation,/Qt\.quit\(\)/);
  assert.match(animation,/Easing\.InOutCubic/);
  assert.match(read('applications/coding-mode.desktop'),/Icon=applications-development/);
});
test('Previous fixes for power button, keyboard and lock screen stay included',()=>{
  const install=read('install.sh');
  assert.match(install,/lockscreen-sync/);
  assert.match(read('update.sh'),/--keep-keyboard/);
  assert.match(read('bin/lockscreen-sync'),/cmp -s/);
  assert.match(read('src/tabletd/tabletd.cpp'),/PowerButtonAction/);
  for(const f of ['install.sh','update.sh','bin/appearance','bin/shell-style','scripts/install-material-icons.sh','bin/app-icons-refresh']){
    const test=cp.spawnSync('bash',['-n',path.join(root,f)]);
    assert.equal(test.status,0,`${f}: ${test.stderr}`);
  }
});
