// autodeps — installs the npm packages the code uses when they are missing, so a customer can upload a bot or an app
// WITHOUT a package.json. Runs at server start from the egg's startup line (embedded there as base64; see build.php).
//
// It reads the .js/.mjs/.cjs/.ts files (never node_modules), collects every require('x') / import ... from 'x' /
// import('x') / export ... from 'x', drops relative paths and Node's own modules, and installs what is not in
// node_modules yet. If there is no package.json it creates a minimal one first, so what gets installed is recorded
// there and the next start is fast (the egg's own `npm install` then takes over).
//
// It stays out of real projects: when the customer's own package.json lists dependencies, npm installs those and
// autodeps does nothing (a bot's optional or leftover require()s — an old fallback in a try/catch, a file that is
// never run — would otherwise be installed on every start, some of them never succeeding). A package.json that
// autodeps made itself carries "autodeps": true and keeps being looked after.
//
// Written for Node 12+ (the oldest image the egg offers): no ?. / ?? / other newer syntax. Never stops the server
// from starting: every failure is reported and the start carries on.
'use strict';

var fs = require('fs');
var path = require('path');
var childProcess = require('child_process');
var builtinModules = require('module').builtinModules || [];

var ROOT = process.cwd();
var MAX_FILES = 5000;
var MAX_BYTES = 2 * 1024 * 1024;
var MAX_DEPTH = 10;
var SKIP_DIRS = { node_modules: 1, '.git': 1, '.npm': 1, '.cache': 1, '.local': 1, '.config': 1, '.pm2': 1 };
var CODE_FILE = /\.(c|m)?(j|t)sx?$/i;
var NPM_NAME = /^(@[a-z0-9][a-z0-9._~-]*\/)?[a-z0-9][a-z0-9._~-]*$/;
var MAX_ONE_BY_ONE = 8; // after the whole list failed: at most this many are tried alone (each is a full npm run)

function log(message) {
    process.stdout.write('[autodeps] ' + message + '\n');
}

/** Node's own modules: fs, path, fs/promises, node:test … never installed from npm. */
var BUILTIN = {};
builtinModules.forEach(function (m) {
    BUILTIN[m] = 1;
    BUILTIN[m.replace(/^node:/, '')] = 1;
});

function codeFiles(dir, depth, out) {
    if (depth > MAX_DEPTH || out.length >= MAX_FILES) {
        return out;
    }
    var entries;
    try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
        return out;
    }
    for (var i = 0; i < entries.length && out.length < MAX_FILES; i++) {
        var entry = entries[i];
        var full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            if (!SKIP_DIRS[entry.name]) {
                codeFiles(full, depth + 1, out);
            }
        } else if (entry.isFile() && CODE_FILE.test(entry.name) && !/\.d\.ts$/i.test(entry.name)) {
            out.push(full);
        }
    }

    return out;
}

/**
 * Comments out of the way, so a commented-out require is not installed. Strings are copied as they are, so a // or
 * a /* inside a string (a URL, a path) is never mistaken for a comment and never hides the code after it.
 */
function stripComments(source) {
    var out = '';
    var i = 0;
    var n = source.length;
    while (i < n) {
        var c = source.charAt(i);
        var next = source.charAt(i + 1);
        if (c === '/' && next === '/') {
            while (i < n && source.charAt(i) !== '\n') {
                i++;
            }
        } else if (c === '/' && next === '*') {
            var end = source.indexOf('*/', i + 2);
            i = end === -1 ? n : end + 2;
            out += ' ';
        } else if (c === '\'' || c === '"' || c === '`') {
            var start = i;
            i++;
            while (i < n && source.charAt(i) !== c) {
                if (source.charAt(i) === '\\') {
                    i++;
                } else if (c !== '`' && source.charAt(i) === '\n') {
                    break; // an unclosed quote ends at the line, like JavaScript itself
                }
                i++;
            }
            i++;
            out += source.slice(start, i);
        } else {
            out += c;
            i++;
        }
    }

    return out;
}

/** Every module specifier written as a plain string literal. require(someVariable) cannot be known and is ignored. */
function specifiers(source) {
    var found = [];
    var patterns = [
        /\brequire\s*\(\s*(['"`])([^'"`\s]+)\1\s*\)/g,
        /\bimport\s*\(\s*(['"`])([^'"`\s]+)\1\s*\)/g,
        /\bimport\s+(?:[\w*{}\s,$]+?\s+from\s+)?(['"])([^'"\s]+)\1/g,
        /\bexport\s+(?:\*|\{[^}]*\}|\*\s+as\s+\w+)\s+from\s+(['"])([^'"\s]+)\1/g,
    ];
    patterns.forEach(function (re) {
        var m;
        while ((m = re.exec(source)) !== null) {
            found.push(m[2]);
        }
    });

    return found;
}

/**
 * 'lodash/fp' -> 'lodash', '@scope/pkg/sub' -> '@scope/pkg'. Null for anything that is not an npm package:
 * relative or absolute paths, #subpath imports, node: / data: / npm: URLs, Node's own modules, invalid names.
 */
function packageName(spec) {
    if (!spec || spec.charAt(0) === '.' || spec.charAt(0) === '/' || spec.charAt(0) === '#' || spec.indexOf(':') !== -1) {
        return null;
    }
    var parts = spec.split('/');
    var name = spec.charAt(0) === '@' ? (parts.length >= 2 ? parts[0] + '/' + parts[1] : null) : parts[0];
    if (!name || BUILTIN[name] || BUILTIN[spec] || name.length > 214 || !NPM_NAME.test(name)) {
        return null;
    }

    return name;
}

function installed(name) {
    return fs.existsSync(path.join(ROOT, 'node_modules', name, 'package.json'));
}

function npm(args) {
    // AUTODEPS_NPM is only for the tests (a fake npm written in JS); on a server it is always the real npm
    var fake = process.env.AUTODEPS_NPM;
    var result = fake
        ? childProcess.spawnSync(process.execPath, [fake].concat(args), { cwd: ROOT, stdio: 'inherit' })
        : childProcess.spawnSync('npm', args, { cwd: ROOT, stdio: 'inherit' });

    return result.status === 0;
}

function main() {
    var ownName = null;
    var pkgFile = path.join(ROOT, 'package.json');
    if (fs.existsSync(pkgFile)) {
        var pkg;
        try {
            pkg = JSON.parse(fs.readFileSync(pkgFile, 'utf8')) || {};
        } catch (e) {
            log('package.json is not valid JSON — leaving it alone, nothing installed');

            return;
        }
        ownName = pkg.name || null;
        var listed = Object.keys(pkg.dependencies || {}).length + Object.keys(pkg.devDependencies || {}).length;
        if (listed > 0 && pkg.autodeps !== true) {
            log('skipped: package.json lists the dependencies (npm installs those). A missing one: add it to package.json or to "Additional Node packages".');

            return;
        }
    }

    var wanted = {};
    codeFiles(ROOT, 0, []).forEach(function (file) {
        var source;
        try {
            if (fs.statSync(file).size > MAX_BYTES) {
                return;
            }
            source = fs.readFileSync(file, 'utf8');
        } catch (e) {
            return;
        }
        specifiers(stripComments(source)).forEach(function (spec) {
            var name = packageName(spec);
            if (name && name !== ownName) {
                wanted[name] = 1;
            }
        });
    });

    var missing = Object.keys(wanted).sort().filter(function (name) {
        return !installed(name);
    });
    if (missing.length === 0) {
        log('every package the code uses is installed');

        return;
    }

    if (!fs.existsSync(pkgFile)) {
        fs.writeFileSync(pkgFile, JSON.stringify({ name: 'server', version: '1.0.0', private: true, autodeps: true }, null, 2) + '\n');
        log('no package.json — created one, so what is installed now is remembered');
    }

    log('installing: ' + missing.join(' '));
    var base = ['install', '--save', '--no-audit', '--no-fund'];
    if (npm(base.concat(missing))) {
        return;
    }

    // One bad name (a typo, a private package) makes npm refuse the whole list: try them one by one instead —
    // quietly (npm's warnings were already shown once) and only a few, so a long list cannot hold the start up
    var alone = missing.slice(0, MAX_ONE_BY_ONE);
    var untried = missing.slice(MAX_ONE_BY_ONE);
    log('installing them together failed — trying ' + (untried.length > 0 ? 'the first ' + alone.length : 'them') + ' one by one');
    var failed = alone.filter(function (name) {
        return !npm(base.concat(['--loglevel=error', name]));
    });
    if (failed.length > 0) {
        log('could not install: ' + failed.join(' ') + ' (check the name, or add it to "Additional Node packages")');
    }
    if (untried.length > 0) {
        log('not tried: ' + untried.join(' ') + ' — add the ones the app needs to package.json or "Additional Node packages"');
    }
}

try {
    main();
} catch (e) {
    log('skipped: ' + (e && e.message ? e.message : e));
}
