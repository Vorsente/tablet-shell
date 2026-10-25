const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');

test('Qt diagnostics are disabled directly in each entry point, without undeclared helpers', () => {
  const sources = [
    'src/tablet-keyboard/main.cpp', 'src/tablet-settings/main.cpp',
    'src/tablet-greeter/main.cpp', 'src/tabletshell/main.cpp',
    'src/webapp-runner/main.cpp', 'src/tabletd/tabletd.cpp',
    'src/tabletd/tablet-tools.cpp',
  ];
  for (const file of sources) {
    const source = fs.readFileSync(path.join(root, file), 'utf8');
    assert.match(source, /#include\s*<QtCore\/qlogging\.h>/, file);
    assert.match(source, /qInstallMessageHandler\s*\(/, file);
    assert.doesNotMatch(source, /disableQtLogging\s*\(/, file);
  }
});
