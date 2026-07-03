/**
 * Fetches FULL level-up learnsets for every species in species.csv (Gen 1-7),
 * plus complete move data (with battle-effect metadata) for every referenced
 * move, from PokeAPI. Data matches pokemondb (both derive from the same games).
 *
 * For each species we take the level-up moveset from the LATEST version group it
 * appears in (what pokemondb shows by default).
 *
 * Outputs:
 *   resources/learnsets.csv  → species_id,move_id,level
 *   resources/moves.csv      → id,name,type,category,power,accuracy,pp,priority,
 *                              min_hits,max_hits,ailment,ailment_chance,crit_rate,
 *                              drain,healing,flinch_chance,stat_chance,target,stat_changes
 *
 * Run: node pokemon/pokemonData/fetch_all_data.js
 */

const https = require('https');
const fs    = require('fs');
const path  = require('path');

const RES   = path.join(__dirname, '../pokemon/pokemonServer/src/main/resources');
const SPECIES_CSV   = path.join(RES, 'species.csv');
const LEARNSETS_OUT = path.join(RES, 'learnsets.csv');
const MOVES_OUT     = path.join(RES, 'moves.csv');
const CACHE = path.join(__dirname, '.pokeapi_cache');

if (!fs.existsSync(CACHE)) fs.mkdirSync(CACHE, { recursive: true });

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function rawGet(url) {
    return new Promise((resolve, reject) => {
        https.get(url, { headers: { 'User-Agent': 'PokeWorld/1.0' } }, res => {
            if (res.statusCode === 301 || res.statusCode === 302)
                return rawGet(res.headers.location).then(resolve).catch(reject);
            if (res.statusCode !== 200) { res.resume(); return reject(new Error('HTTP ' + res.statusCode + ' ' + url)); }
            let d = ''; res.on('data', c => d += c);
            res.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { reject(e); } });
        }).on('error', reject);
    });
}

// Cached GET with retries.
async function get(url, cacheKey) {
    const cf = path.join(CACHE, cacheKey + '.json');
    if (fs.existsSync(cf)) { try { return JSON.parse(fs.readFileSync(cf, 'utf8')); } catch {} }
    let lastErr;
    for (let attempt = 0; attempt < 4; attempt++) {
        try {
            const data = await rawGet(url);
            fs.writeFileSync(cf, JSON.stringify(data));
            await sleep(80);
            return data;
        } catch (e) { lastErr = e; await sleep(400 * (attempt + 1)); }
    }
    throw lastErr;
}

function idFromUrl(url) {
    const p = url.replace(/\/$/, '').split('/');
    return parseInt(p[p.length - 1], 10);
}

function titleCase(slug) {
    return slug.split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}

function capType(t) { return t.charAt(0).toUpperCase() + t.slice(1); }

const AILMENT = {
    paralysis: 'PARALYZE', sleep: 'SLEEP', poison: 'POISON',
    burn: 'BURN', freeze: 'FREEZE', confusion: 'CONFUSE',
};
const STAT_SHORT = {
    attack: 'atk', defense: 'def', 'special-attack': 'spa',
    'special-defense': 'spd', speed: 'spe', accuracy: 'acc', evasion: 'eva',
};

function readSpeciesIds() {
    const lines = fs.readFileSync(SPECIES_CSV, 'utf8').split('\n').filter(l => l.trim());
    return lines.slice(1).map(l => parseInt(l.split(',')[0], 10)).filter(n => !isNaN(n));
}

async function main() {
    const speciesIds = readSpeciesIds();
    console.log(`Fetching learnsets for ${speciesIds.length} species...`);

    const learnRows = ['species_id,move_id,level'];
    const moveIds = new Set();
    let done = 0;

    for (const sid of speciesIds) {
        let mon;
        try { mon = await get(`https://pokeapi.co/api/v2/pokemon/${sid}/`, `pkmn_${sid}`); }
        catch (e) { console.error(`\n #${sid} failed: ${e.message}`); continue; }

        const entries = []; // {moveId, level}
        for (const me of mon.moves) {
            // Among level-up entries, take the one from the latest version group.
            let best = null;
            for (const vgd of me.version_group_details) {
                if (vgd.move_learn_method.name !== 'level-up') continue;
                const vgId = idFromUrl(vgd.version_group.url);
                if (!best || vgId > best.vgId) best = { vgId, level: vgd.level_learned_at };
            }
            if (best) {
                const moveId = idFromUrl(me.move.url);
                entries.push({ moveId, level: best.level <= 0 ? 1 : best.level });
                moveIds.add(moveId);
            }
        }
        entries.sort((a, b) => a.level - b.level || a.moveId - b.moveId);
        for (const e of entries) learnRows.push(`${sid},${e.moveId},${e.level}`);

        done++;
        if (done % 25 === 0) process.stdout.write(`  learnsets ${done}/${speciesIds.length}\r`);
    }
    fs.writeFileSync(LEARNSETS_OUT, learnRows.join('\n') + '\n');
    console.log(`\nWrote ${learnRows.length - 1} learnset rows. ${moveIds.size} unique moves referenced.`);

    console.log('Fetching move data...');
    const moveRows = ['id,name,type,category,power,accuracy,pp,priority,min_hits,max_hits,ailment,ailment_chance,crit_rate,drain,healing,flinch_chance,stat_chance,target,stat_changes'];
    const sortedMoveIds = [...moveIds].sort((a, b) => a - b);
    let mdone = 0;

    for (const mid of sortedMoveIds) {
        let m;
        try { m = await get(`https://pokeapi.co/api/v2/move/${mid}/`, `move_${mid}`); }
        catch (e) { console.error(`\n move #${mid} failed: ${e.message}`); continue; }

        const name = titleCase(m.name);
        const type = capType(m.type.name);
        const dc = m.damage_class ? m.damage_class.name : 'status';
        const category = dc === 'physical' ? 'Physical' : dc === 'special' ? 'Special' : 'Status';
        const power = m.power || 0;
        const accuracy = m.accuracy || 0;       // 0 = never-misses (status/self)
        const pp = m.pp || 0;
        const priority = m.priority || 0;
        const meta = m.meta || {};
        const minHits = meta.min_hits || 1;
        const maxHits = meta.max_hits || 1;
        const ailment = AILMENT[meta.ailment ? meta.ailment.name : 'none'] || '';
        const ailmentChance = meta.ailment_chance || 0;
        const critRate = meta.crit_rate || 0;
        const drain = meta.drain || 0;          // + = heal % of dmg, - = recoil
        const healing = meta.healing || 0;      // % of max HP
        const flinch = meta.flinch_chance || 0;
        const statChance = meta.stat_chance || 0;
        const target = (m.target && m.target.name && m.target.name.includes('user')) ? 'self' : 'foe';

        const statChanges = (m.stat_changes || [])
            .map(sc => `${STAT_SHORT[sc.stat.name] || sc.stat.name}:${sc.change}`)
            .join('|');

        moveRows.push([
            mid, name, type, category, power, accuracy, pp, priority,
            minHits, maxHits, ailment, ailmentChance, critRate, drain, healing,
            flinch, statChance, target, statChanges
        ].join(','));

        mdone++;
        if (mdone % 50 === 0) process.stdout.write(`  moves ${mdone}/${sortedMoveIds.length}\r`);
    }
    fs.writeFileSync(MOVES_OUT, moveRows.join('\n') + '\n');
    console.log(`\nWrote ${moveRows.length - 1} moves.`);
    console.log('Done.');
}

main().catch(e => { console.error(e); process.exit(1); });
