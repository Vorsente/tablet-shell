// Run with node --test tests/panels.test.cjs. Models the Plasma scripting API;
// does not replace a real Plasma 6 / Wayland integration test.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const dir = path.join(__dirname, '../shell/tablet-mode');
const morph = fs.readFileSync(path.join(dir, 'morph-panels.js'), 'utf8');
const layout = fs.readFileSync(path.join(dir, 'layout-tablet.js'), 'utf8');
const T = 'org.kde.plasma.';
function fixture() {
    const live = [], logs = [];
    let created = 0;
    function Panel() {
        this.items = []; this.location = 'bottom'; this.height = 0;
        this.hiding = 'autohide'; this.created = ++created;
        this.widgets = () => this.items.slice();
        this.remove = () => live.splice(live.indexOf(this), 1);
        this.addWidget = type => {
            const parent = this;
            const w = {type, config: {}, writeConfig(k, v) {this.config[k] = v;}, reloadConfig() {},
                remove() {parent.items.splice(parent.items.indexOf(this), 1);}};
            Object.defineProperty(w, 'index', {
                get() {return parent.items.indexOf(w);},
                set(i) {w.remove(); parent.items.splice(i, 0, w);}
            });
            parent.items.push(w); return w;
        };
        live.push(this);
    }
    const ctx = vm.createContext({panels: () => live.slice(), Panel, print: s => logs.push(s), ConfigFile: () => ({readEntry: () => ctx.STYLE || 'apple'}), LAUNCHERS: ['applications:custom.desktop']});
    function phase(tablet, n) {ctx.TABLET = tablet; ctx.PHASE = n; logs.length = 0; vm.runInContext(morph, ctx); return logs.at(-1);}
    function bootstrap() {vm.runInContext(layout, ctx);}
    function apply(tablet) {
        let status = phase(tablet, 1);
        if (status === 'REBUILD') {bootstrap(); status = phase(tablet, 1);}
        if (status !== 'DONE') {phase(tablet, 2); if (!tablet) phase(tablet, 3); status = phase(tablet, 9);}
        assert.equal(status, 'DONE');
    }
    function bar() {return live.find(p => p.items.some(w => w.type === T + 'systemtray'));}
    return {live, logs, Panel, phase, bootstrap, apply, bar, style: s => {ctx.STYLE = s;}};
}
test('empty desktop recovers tablet status bar and window-dodging dock', () => {
    const f = fixture(); f.apply(true);
    assert.equal(f.live.length, 2);
    assert.equal(f.bar().location, 'top');
    for (const p of f.live) {assert.equal(p.hiding, p === f.bar() ? 'none' : 'dodgewindows'); assert.ok(p.height > 0);}
});
test('empty desktop recovers complete PC taskbar', () => {
    const f = fixture(); f.apply(false);
    assert.equal(f.live.length, 1);
    assert.deepEqual(f.bar().items.map(w => w.type), ['kickoff','icontasks','panelspacer','systemtray','digitalclock','showdesktop'].map(t => T+t));
});
test('fast path restores hidden and zero-height panels without recreating widgets', () => {
    for (const tablet of [true, false]) {
        const f = fixture(); f.apply(tablet);
        const widgets = f.live.flatMap(p => p.items);
        f.live.forEach(p => {p.height = 0; p.hiding = 'autohide';});
        f.apply(tablet);
        assert.deepEqual(f.live.flatMap(p => p.items), widgets);
        f.live.forEach(p => {assert.equal(p.hiding, p === f.bar() ? 'none' : 'dodgewindows'); assert.ok(p.height > 0);});
    }
});
test('switching modes preserves tray identity and pinned launchers', () => {
    const f = fixture(); f.apply(true);
    const tray = f.bar().items.find(w => w.type === T+'systemtray');
    for (let i=0; i<12; i++) {
        f.apply(i%2 === 1);
        assert.equal(f.bar().items.find(w => w.type === T+'systemtray'), tray);
        for (const p of f.live) for (const w of p.items) if (w.type === T+'icontasks') assert.deepEqual(Array.from(w.config.launchers), ['applications:custom.desktop']);
    }
});
test('custom user panels survive recovery and mode changes', () => {
    const f = fixture(); const custom = new f.Panel(); custom.addWidget(T+'notes');
    for (const mode of [true, false, true]) {f.apply(mode); assert.ok(f.live.includes(custom)); assert.equal(custom.items.length, 1);}
});
test('bootstrap is idempotent and reuses bar after partial tray failure', () => {
    const f = fixture(); const partial = new f.Panel(); partial.addWidget('org.ipad.statusclock');
    f.bootstrap(); f.bootstrap(); f.apply(true);
    assert.equal(f.bar(), partial); assert.equal(f.live.length, 2);
});
test('missing required widgets are repaired instead of reporting false readiness', () => {
    for (const tablet of [true, false]) {
        const f = fixture(); f.apply(tablet);
        f.bar().items.find(w => w.type === T+'panelspacer').remove();
        if (!tablet) f.bar().items.find(w => w.type === T+'digitalclock').remove();
        f.apply(tablet);
        assert.ok(f.bar().items.some(w => w.type === T+'panelspacer'));
        if (!tablet) assert.ok(f.bar().items.some(w => w.type === T+'digitalclock'));
    }
});
test('phase 9 does not accept an incomplete panel as DONE', () => {
    const f = fixture(); f.apply(false);
    f.bar().items.find(w => w.type === T+'showdesktop').remove();
    assert.equal(f.phase(false, 9), 'UNORDERED');
});
test('ordering is restored without recreating the tray', () => {
    const f = fixture(); f.apply(true); f.bar().items.reverse();
    assert.equal(f.phase(true, 9), 'DONE');
    assert.equal(f.bar().items[0].type, 'org.ipad.statusclock');
});

test('live visual style changes resize managed panels without changing tray or auto-hide', () => {
    const f = fixture(); f.apply(true);
    const tray = f.bar().items.find(w => w.type === T+'systemtray');
    for (const style of ['pixel','apple','pixel']) {
        f.style(style); f.apply(true);
        assert.equal(f.bar().height, style === 'pixel' ? 32 : 28);
        const dock = f.live.find(p => p !== f.bar());
        assert.equal(dock.height, style === 'pixel' ? 72 : 64);
        assert.equal(dock.hiding, 'dodgewindows');
        assert.equal(f.bar().items.find(w => w.type === T+'systemtray'), tray);
        assert.equal(f.bar().items[0].config.shellStyle, style);
    }
});
