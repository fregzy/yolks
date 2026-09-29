// node-check — which Node.js this app needs, run by vndel-node before the app starts.
//
// Reads what the app itself says: package.json "engines.node", .nvmrc / .node-version, and the "engines.node" of
// every package package.json depends on (from node_modules). When the Node.js this server runs does not satisfy all
// of them, it prints ONE line (the panel's "Node.js version" feature opens a window on it) and writes the details to
// .vndel/node-version.json for that window: what is needed, by which package, and which Node.js to choose.
//
// Ranges are checked with npm's own semver. Written for Node 12+. Never stops the server: it only reports.
'use strict';

var fs = require('fs');
var path = require('path');

var ROOT = process.cwd();
var STATE_DIR = path.join(ROOT, '.vndel');
var STATE_FILE = path.join(STATE_DIR, 'node-version.json');
var LINE = '[vndel] Node.js version:';

function semverLib() {
    var tries = [process.env.VNDEL_SEMVER, '/usr/local/lib/node_modules/npm/node_modules/semver'];
    for (var i = 0; i < tries.length; i++) {
        if (tries[i]) {
            try {
                return require(tries[i]);
            } catch (e) {
                // next
            }
        }
    }

    return null;
}

function readJson(file) {
    try {
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (e) {
        return null;
    }
}

/** "20", "v20.11.1", "20.x" -> "20.x"; "lts/*", "node", garbage -> null */
function versionFile(name) {
    var text;
    try {
        text = fs.readFileSync(path.join(ROOT, name), 'utf8').trim();
    } catch (e) {
        return null;
    }
    var m = /^v?(\d{1,2})(\.|$)/.exec(text);

    return m ? m[1] + '.x' : null;
}

function constraints(semver) {
    var out = [];
    var add = function (range, source) {
        if (typeof range === 'string' && range.trim() !== '' && semver.validRange(range.trim())) {
            out.push({ range: range.trim(), source: source });
        }
    };

    var pkg = readJson(path.join(ROOT, 'package.json')) || {};
    add(pkg.engines && pkg.engines.node, 'package.json');
    add(versionFile('.nvmrc'), '.nvmrc');
    add(versionFile('.node-version'), '.node-version');

    Object.keys(pkg.dependencies || {}).sort().forEach(function (name) {
        var dep = readJson(path.join(ROOT, 'node_modules', name, 'package.json'));
        if (dep && dep.engines && dep.engines.node) {
            add(String(dep.engines.node), name + '@' + (dep.version || '?'));
        }
    });

    return out;
}

/** The Node.js to choose: the smallest even (long-term support) major above this one that satisfies everything. */
function recommend(semver, needs, current, majors) {
    var fits = majors.filter(function (m) {
        return needs.every(function (n) {
            return semver.satisfies(m + '.999.999', n.range);
        });
    });
    if (fits.length === 0) {
        return null;
    }
    var up = fits.filter(function (m) { return m > current; });
    var even = up.filter(function (m) { return m % 2 === 0; });
    if (even.length > 0) {
        return even[0];
    }
    if (up.length > 0) {
        return up[0];
    }

    return fits[fits.length - 1]; // only older ones fit (the app caps its Node.js version)
}

function main() {
    var semver = semverLib();
    if (semver === null) {
        return;
    }
    var current = semver.major(process.version);
    var majors = (process.env.VNDEL_NODE_MAJORS || '12 13 14 15 16 17 18 19 20 21 22 23 24 25 26')
        .split(/\s+/).map(Number).filter(function (m) { return m > 0; }).sort(function (a, b) { return a - b; });

    var all = constraints(semver);
    var unmet = all.filter(function (n) {
        return !semver.satisfies(process.version, n.range);
    });

    if (unmet.length === 0) {
        try {
            fs.unlinkSync(STATE_FILE);
        } catch (e) {
            // there was none
        }

        return;
    }

    var pick = recommend(semver, all, current, majors);
    var needs = unmet.slice(0, 5).map(function (n) { return n.source + ' needs ' + n.range; }).join(', ') + (unmet.length > 5 ? ', …' : '');
    var advice = pick !== null
        ? 'Recommended: Node.js ' + pick + ' — choose it in Startup → Docker Image.'
        : 'No Node.js version offered here satisfies all of them.';
    // one colour for the whole line: the panel looks for the plain text "[vndel] Node.js version:" in it
    process.stdout.write('\x1b[1;33m' + LINE + ' this server runs Node.js ' + current + ', but ' + needs + '. ' + advice + '\x1b[0m\n');

    try {
        fs.mkdirSync(STATE_DIR, { recursive: true });
        fs.writeFileSync(STATE_FILE, JSON.stringify({
            current: current,
            currentVersion: process.version,
            recommended: pick,
            needs: unmet.map(function (n) { return { source: n.source, range: n.range }; }),
            checkedAt: new Date().toISOString(),
        }, null, 2) + '\n');
    } catch (e) {
        // the line above is what matters
    }
}

try {
    main();
} catch (e) {
    // never in the way of the app
}
