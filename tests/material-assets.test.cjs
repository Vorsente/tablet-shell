const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.join(__dirname, '..');
const read = p => fs.readFileSync(path.join(root,p),'utf8');
test('both Pixel packages resolve to bundled color schemes and complete Plasma frames', () => {
  for(const mode of ['light','dark']) {
    const defaults = read(`shell/look-and-feel/org.tabletshell.pixel.${mode}/contents/defaults`);
    const scheme = defaults.match(/^ColorScheme=(.+)$/m)[1];
    const theme = defaults.match(/^name=(.+)$/m)[1];
    assert.equal(JSON.parse(read(`shell/desktoptheme/${theme}/metadata.json`)).KPlugin.Id,theme);
    const colors = read(`shell/color-schemes/${scheme}.colors`);
    assert.equal(colors,read(`shell/desktoptheme/${theme}/colors`));
    for(const role of ['Window','View','Button','Tooltip','Selection','Header']) assert.ok(colors.includes(`[Colors:${role}]`));
    for(const asset of ['widgets/panel-background.svg','widgets/background.svg','dialogs/background.svg','widgets/tooltip.svg']) {
      const svg = read(`shell/desktoptheme/${theme}/${asset}`);
      const ids = [...svg.matchAll(/id="([^"]+)"/g)].map(m=>m[1]);
      assert.equal(new Set(ids).size, ids.length);
      for(const prefix of ['','mask-']) for(const pos of ['top','bottom','left','right','center','topleft','topright','bottomleft','bottomright']) assert.ok(ids.includes(prefix+pos),`${asset}: ${prefix+pos}`);
    }
  }
});
test('managed-file inventory owns new resources and still preserves a reused keyboard', () => {
  const code = `import importlib.util,json,pathlib
s=importlib.util.spec_from_file_location('managed','scripts/managed-files.py')
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
a=m.source_map(pathlib.Path('.'),reuse_keyboard=True)
print(json.dumps(list(a)))`;
  const r=cp.spawnSync('python3',['-c',code],{cwd:root,encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);
  const files=JSON.parse(r.stdout);
  for(const mode of ['light','dark']) assert.ok(files.includes(`.local/share/plasma/desktoptheme/tablet-pixel-${mode}/widgets/panel-background.svg`));
  assert.ok(files.includes('.local/share/color-schemes/TabletPixelDark.colors'));
  assert.ok(!files.some(f=>f.startsWith('.local/share/tablet-keyboard/')));
});
