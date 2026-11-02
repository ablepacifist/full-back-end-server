/**
 * Fetches accurate Gen 1 (Red/Blue) level-up learnsets for all 151 Pokemon
 * from PokeAPI and writes learnsets.csv to the pokemonServer resources directory.
 *
 * Run: node pokemon/pokemonData/fetch_gen1_learnsets.js
 */

const https = require('https');
const fs    = require('fs');
const path  = require('path');

const OUT = path.join(__dirname,
    '../pokemon/pokemonServer/src/main/resources/learnsets.csv');

function get(url) {
    return new Promise((resolve, reject) => {
        https.get(url, { headers: { 'User-Agent': 'PokeWorld-DataFetch/1.0' } }, res => {
            if (res.statusCode === 301 || res.statusCode === 302) {
                return get(res.headers.location).then(resolve).catch(reject);
            }
            let data = '';
            res.on('data', c => data += c);
            res.on('end', () => {
                try { resolve(JSON.parse(data)); }
                catch (e) { reject(new Error(`JSON parse failed for ${url}: ${e.message}`)); }
            });
        }).on('error', reject);
    });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
    const rows = ['species_id,move_id,level'];
    let totalMoves = 0;

    for (let id = 1; id <= 151; id++) {
        process.stdout.write(`Fetching #${id}...             \r`);

        let data;
        try {
            data = await get(`https://pokeapi.co/api/v2/pokemon/${id}/`);
        } catch (e) {
            console.error(`\nFailed to fetch #${id}: ${e.message}, skipping`);
            await sleep(500);
            continue;
        }

        const levelMoves = [];

        for (const moveEntry of data.moves) {
            for (const vgd of moveEntry.version_group_details) {
                if (vgd.version_group.name      === 'red-blue' &&
                    vgd.move_learn_method.name  === 'level-up') {

                    // Extract move ID from URL e.g. ".../move/10/" → 10
                    const parts  = moveEntry.move.url.replace(/\/$/, '').split('/');
                    const moveId = parseInt(parts[parts.length - 1], 10);

                    // Only Gen 1 moves (IDs 1-165)
                    if (moveId >= 1 && moveId <= 165) {
                        levelMoves.push({ moveId, level: vgd.level_learned_at });
                    }
                }
            }
        }

        // Sort: by level ascending, then move ID for determinism
        levelMoves.sort((a, b) => a.level - b.level || a.moveId - b.moveId);

        for (const { moveId, level } of levelMoves) {
            rows.push(`${id},${moveId},${level}`);
        }

        totalMoves += levelMoves.length;
        await sleep(120); // polite rate limiting
    }

    fs.writeFileSync(OUT, rows.join('\n') + '\n', 'utf8');
    console.log(`\nDone. ${rows.length - 1} learnset entries for 151 Pokemon written to:`);
    console.log(`  ${OUT}`);
}

main().catch(e => { console.error(e); process.exit(1); });
