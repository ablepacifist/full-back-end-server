/**
 * Converts Pokemon.csv (all gens, includes Mega/Alolan etc.) to a clean
 * species.csv for Gen 1-7 base-form Pokemon only (IDs 1-809).
 *
 * Run: node pokemon/pokemonData/convert_species.js
 */

const fs   = require('fs');
const path = require('path');

const IN      = path.join(__dirname, 'pokemonData/Pokemon.csv');
const OUT     = path.join(__dirname,
    '../pokemon/pokemonServer/src/main/resources/species.csv');
const SPRITES = path.join(__dirname, '../pogo_assets/Images/Pokemon');

function parseRarity(bst) {
    if (bst <  400) return 1;
    if (bst <= 449) return 2;
    if (bst <= 499) return 3;
    if (bst <= 599) return 4;
    return 5;
}

// Parse CSV respecting quoted fields
function parseLine(line) {
    const fields = [];
    let cur = '', inQ = false;
    for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (c === '"') { inQ = !inQ; continue; }
        if (c === ',' && !inQ) { fields.push(cur); cur = ''; continue; }
        cur += c;
    }
    fields.push(cur);
    return fields.map(f => f.trim());
}

// Build set of IDs that have a base-form sprite available
const spriteFiles = new Set(fs.readdirSync(SPRITES));
function hasSprite(id) {
    return spriteFiles.has(`pokemon_icon_${String(id).padStart(3, '0')}_00.png`);
}

const raw  = fs.readFileSync(IN, 'utf8').split('\n').filter(l => l.trim());
const header = parseLine(raw[0]);

// Expected columns: ID, Name, Form, Type1, Type2, Total, HP, Attack, Defense, Sp. Atk, Sp. Def, Speed, Generation
const idx = {};
header.forEach((h, i) => idx[h] = i);

const rows   = ['id,name,type1,type2,rarity,hp,attack,defense,sp_atk,sp_def,speed'];
const seen   = new Set(); // deduplicate by ID (keep first = base form)
let   skipped = 0, added = 0;

for (let i = 1; i < raw.length; i++) {
    const line = raw[i].trim();
    if (!line) continue;
    const f = parseLine(line);

    const id         = parseInt(f[idx['ID']], 10);
    const form       = (f[idx['Form']] || '').trim();
    const generation = parseInt(f[idx['Generation']], 10);

    // Skip alternate forms (Mega, Alolan, Galarian, etc.)
    if (form !== '') { skipped++; continue; }
    // Limit to IDs 1-809 (Gen 1-7 scope)
    if (id < 1 || id > 809) { skipped++; continue; }
    // Skip duplicate IDs
    if (seen.has(id)) { skipped++; continue; }
    // Only include Pokemon that have a sprite file in pogo_assets
    if (!hasSprite(id)) { skipped++; continue; }
    seen.add(id);

    const name   = f[idx['Name']];
    const type1  = f[idx['Type1']];
    const type2  = (f[idx['Type2']] || '').trim() === '' ? '' : f[idx['Type2']];
    const bst    = parseInt(f[idx['Total']], 10);
    const hp     = parseInt(f[idx['HP']], 10);
    const atk    = parseInt(f[idx['Attack']], 10);
    const def    = parseInt(f[idx['Defense']], 10);
    const spAtk  = parseInt(f[idx['Sp. Atk']], 10);
    const spDef  = parseInt(f[idx['Sp. Def']], 10);
    const speed  = parseInt(f[idx['Speed']], 10);
    const rarity = parseRarity(bst);

    rows.push(`${id},${name},${type1},${type2},${rarity},${hp},${atk},${def},${spAtk},${spDef},${speed}`);
    added++;
}

fs.writeFileSync(OUT, rows.join('\n') + '\n', 'utf8');
console.log(`Done. ${added} base-form Pokemon (Gen 1-7) written to:`);
console.log(`  ${OUT}`);
console.log(`  (${skipped} alternate forms/out-of-range skipped)`);
