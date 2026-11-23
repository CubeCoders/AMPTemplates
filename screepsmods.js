'use strict';
// Adds the Screeps mods and bots listed in AMP's "Mods" setting to the world's mods.json.
// Usage (run from the world folder): node screepsmods.js <server folder> "<package> <package>..."
// Entries that point into the server folder's node_modules are managed here; all other entries are kept.
const fs = require('fs').promises;
const path = require('path');

const worldDir = process.cwd();
const modulesDir = path.join(path.resolve(process.argv[2] || '.'), 'node_modules');
const wanted = (process.argv[3] || '')
    .split(/[\s,]+/)
    .filter(Boolean)
    .map(spec => spec.match(/^(@?[^@]+)/)[1]);
const modFile = path.join(worldDir, 'mods.json');

const inModules = entry => path.resolve(worldDir, entry).indexOf(modulesDir + path.sep) === 0;
const relative = target => path.relative(worldDir, target).split(path.sep).join('/');

async function main() {
    let json = {};
    try {
        json = JSON.parse(await fs.readFile(modFile, 'utf8'));
    } catch (e) {
        if (e.code !== 'ENOENT') {
            throw new Error(`Cannot read ${modFile}: ${e.message}`);
        }
    }
    json.mods = (json.mods instanceof Array ? json.mods : []).filter(entry => !inModules(entry));
    json.bots = json.bots && typeof json.bots === 'object' ? json.bots : {};
    for (const name of Object.keys(json.bots)) {
        if (inModules(json.bots[name])) {
            delete json.bots[name];
        }
    }

    for (const name of wanted) {
        const dir = path.join(modulesDir, name);
        let pkg;
        let entry;
        try {
            pkg = JSON.parse(await fs.readFile(path.join(dir, 'package.json'), 'utf8'));
            entry = require.resolve(dir);
        } catch (e) {
            console.error(`"${name}" is not installed or has no entry point; skipping`);
            continue;
        }
        if (pkg.screeps_bot) {
            json.bots[name] = relative(path.dirname(entry));
            console.log(`Bot "${name}" enabled`);
        }
        if (pkg.screeps_mod) {
            json.mods.push(relative(entry));
            console.log(`Mod "${name}" enabled`);
        }
        if (!pkg.screeps_bot && !pkg.screeps_mod) {
            console.error(`"${name}" is not marked as a Screeps mod or bot; skipping`);
        }
    }

    await fs.writeFile(modFile, JSON.stringify(json, null, 2));
}

main().catch(e => {
    console.error(e.message);
    process.exit(1);
});
