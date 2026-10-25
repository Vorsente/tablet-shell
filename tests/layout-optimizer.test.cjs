const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const qml = fs.readFileSync(path.join(__dirname, '../shell/plasmoids/org.ipad.homescreen/contents/ui/main.qml'), 'utf8');
const start = qml.indexOf('    readonly property var placement: {');
const end = qml.indexOf('    // Reuse the precomputed per-page index', start);
assert.ok(start >= 0 && end > start);
const code = qml.slice(start + '    readonly property var placement: {'.length, end).replace(/\n    }\s*$/, '');
function optimized(layout, columns, rows) {
    const spanOf = (e) => e && typeof e === 'object' && e.widget !== undefined
        ? [Math.min(columns, e.size === 'wide' ? 4 : 2), Math.min(rows, 2)] : [1, 1];
    const ctx = { layout, columns, rows, spanOf };
    return vm.runInNewContext(`(function() {${code}\n})()`, ctx);
}
function reference(layout, columns, rows) {
    const pos = [];
    let page = 0;
    let occupied = [];
    for (const entry of layout) {
        const widget = entry && typeof entry === 'object' && entry.widget !== undefined;
        const w = widget ? Math.min(columns, entry.size === 'wide' ? 4 : 2) : 1;
        const h = widget ? Math.min(rows, 2) : 1;
        let at = null;
        for (let y = 0; y < rows && !at; y++) for (let x = 0; x < columns && !at; x++) {
            if (x + w > columns || y + h > rows) continue;
            let free = true;
            for (let r = y; r < y + h; r++) for (let c = x; c < x + w; c++) {
                if (occupied[r * columns + c]) free = false;
            }
            if (free) at = [x, y];
        }
        if (!at) { page++; occupied = []; at = [0, 0]; }
        for (let r = at[1]; r < at[1] + h; r++) for (let c = at[0]; c < at[0] + w; c++) occupied[r * columns + c] = 1;
        pos.push({page, col: at[0], row: at[1], w, h});
    }
    return pos;
}
test('bit-mask packing matches original first-fit for random desktop arrangements', () => {
    let seed = 0x12345678;
    const random = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 2 ** 32);
    for (let k = 0; k < 100; k++) {
        const columns = 3 + Math.floor(random() * 5), rows = 1 + Math.floor(random() * 9);
        const layout = Array.from({ length: Math.floor(random() * 180) }, (_, i) => {
            const n = random();
            return n < 0.12 ? {widget:'clock',size:'wide'} : n < 0.27 ? {widget:'weather',size:'small'} : `app-${i}`;
        });
        const actual = optimized(layout, columns, rows);
        assert.deepEqual(JSON.parse(JSON.stringify(actual.pos)), reference(layout, columns, rows));
        const fromPages = actual.byPage.flat();
        assert.deepEqual(Array.from(fromPages), layout.map((_, i) => i));
        assert.equal(actual.pages, actual.byPage.length);
    }
});
test('empty grids preserve one page and zero entries', () => {
    const result = optimized([], 5, 4);
    assert.equal(result.pages, 1);
    assert.equal(result.pos.length, 0);
    assert.equal(result.byPage.length, 1);
});
