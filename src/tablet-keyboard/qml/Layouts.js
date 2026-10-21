// Keyboard layouts. A row is a list of keys; a key is
//   [type, label, secondary, width, alternates]
// type: c char, bs backspace, ret return, sh shift, num 123, abc ABC, more #+=, glb language,
//       emo emoji, spc space, hide hide keyboard, gap empty space.
// secondary: typed by flicking the key down (iPad "key flicks"); alternates: long press menu.
// split: index of the first key of the right half in split mode (row 4 has its own split row).
.pragma library

function chars(letters, secondaries, alts) {
    var out = [];
    for (var i = 0; i < letters.length; ++i) {
        var ch = letters[i];
        out.push(["c", ch, secondaries ? (secondaries[i] || "") : "", 1, (alts && alts[ch]) || null]);
    }
    return out;
}

var ALTS = {
    "е": ["ё", "е"], "ь": ["ъ", "ь"], "ё": ["ё", "е"], "ъ": ["ъ", "ь"],
    "a": ["à", "á", "â", "ä", "æ", "ã", "å"], "e": ["è", "é", "ê", "ë", "€"], "i": ["ì", "í", "î", "ï"],
    "o": ["ò", "ó", "ô", "ö", "õ", "ø"], "u": ["ù", "ú", "û", "ü"], "c": ["ç", "©"], "n": ["ñ"], "s": ["ß", "$"],
    "y": ["ÿ"], "z": ["ž"], ".": ["…", "·"], ",": ["„", "“"], "-": ["—", "–", "•"], "'": ["’", "‘", "`"],
    "\"": ["«", "»", "“", "”", "„"], "?": ["¿"], "!": ["¡"], "0": ["°", "∅"], "$": ["€", "£", "¥", "₽", "¢"],
    "₽": ["$", "€", "£"], "%": ["‰"], "&": ["§"], "/": ["\\", "|"], "*": ["×", "★"], "+": ["±"], "=": ["≠", "≈"],
    "<": ["≤", "‹", "«"], ">": ["≥", "›", "»"], "(": ["[", "{"], ")": ["]", "}"]
};

function bottom(units, letters) {
    // [123 globe emoji space 123 hide], widths scaled to the row width
    var k = units / 11.5;
    return [["num", letters ? "123" : "ABC", "", 1.5 * k], ["glb", "", "", 1 * k], ["emo", "", "", 1 * k],
            ["spc", "", "", 5 * k], ["num", letters ? "123" : "ABC", "", 1.5 * k], ["hide", "", "", 1.5 * k]];
}
function bottomSplit(units, letters) {
    var k = units / 11.5;
    return {
        left: [["num", letters ? "123" : "ABC", "", 1.5 * k], ["glb", "", "", 1 * k], ["emo", "", "", 1 * k], ["spc", "", "", 2.5 * k]],
        right: [["spc", "", "", 2.5 * k], ["num", letters ? "123" : "ABC", "", 1.5 * k], ["hide", "", "", 1.5 * k]]
    };
}

var en = {
    name: "English", units: 11.5, letters: true,
    rows: [
        { keys: chars("qwertyuiop", "1234567890", ALTS).concat([["bs", "", "", 1.5]]), split: 5 },
        { keys: [["gap", "", "", 0.5]].concat(chars("asdfghjkl", "@#$&*()'\"", ALTS)).concat([["ret", "", "", 2]]), split: 6 },
        { keys: [["sh", "", "", 1.25]].concat(chars("zxcvbnm,.", "%-+=/;:!?", ALTS)).concat([["sh", "", "", 1.25]]), split: 6 },
    ]
};

var ru = {
    name: "Русский", units: 13.5, letters: true,
    rows: [
        { keys: chars("йцукенгшщзхъ", "1234567890-+", ALTS).concat([["bs", "", "", 1.5]]), split: 6 },
        { keys: chars("фывапролджэ", "@#$&*()'\"₽~", ALTS).concat([["ret", "", "", 2.5]]), split: 6 },
        { keys: [["sh", "", "", 1.25]].concat(chars("ячсмитьбюё.", "%_/=;:!?«»,", ALTS)).concat([["sh", "", "", 1.25]]), split: 6 },
    ]
};

var symbols = {
    name: "", units: 11.5, letters: false,
    rows: [
        { keys: chars("1234567890", "", ALTS).concat([["bs", "", "", 1.5]]), split: 5 },
        { keys: [["gap", "", "", 0.5]].concat(chars("-/:;()₽&@", "", ALTS)).concat([["ret", "", "", 2]]), split: 5 },
        { keys: [["more", "#+=", "", 1.25]].concat(chars(".,?!'\"%*+", "", ALTS)).concat([["more", "#+=", "", 1.25]]), split: 5 },
    ]
};

var more = {
    name: "", units: 11.5, letters: false,
    rows: [
        { keys: chars("[]{}#%^*+=", "", ALTS).concat([["bs", "", "", 1.5]]), split: 5 },
        { keys: [["gap", "", "", 0.5]].concat(chars("_\\|~<>€$£", "", ALTS)).concat([["ret", "", "", 2]]), split: 5 },
        { keys: [["more", "123", "", 1.25]].concat(chars(".,?!'\"•…§", "", ALTS)).concat([["more", "123", "", 1.25]]), split: 5 },
    ]
};

// digits / number / phone fields: a calculator-style pad
var numpad = {
    name: "", units: 4, letters: false, pad: true,
    rows: [
        { keys: chars("123", "", null).concat([["bs", "", "", 1]]) },
        { keys: chars("456", "", null).concat([["c", "-", "", 1, null]]) },
        { keys: chars("789", "", null).concat([["ret", "", "", 1]]) },
        { keys: [["c", ",", "", 1, null], ["c", "0", "", 1, null], ["c", ".", "", 1, null], ["hide", "", "", 1]] },
    ]
};
