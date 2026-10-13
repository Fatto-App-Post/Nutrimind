// Analizza ogni file .sql del repository con il parser di PostgreSQL.
// Non esegue niente: controlla solo che la sintassi sia valida, così un
// errore di battitura si vede in CI e non nel SQL Editor, dove il primo
// errore annulla tutto lo script.
//
// Uso: npm install --no-save libpg-query@17 && node scripts/check-sql.mjs

import { readdir, readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
// libpg-query è un modulo CommonJS e va importato dal default: con
// `import { ... } from` Node solleva un errore di export mancante e il
// controllo non parte nemmeno. Dalla 17 la funzione si chiama `parse`
// (prima `parseQuery`) e il parser vero è WebAssembly, quindi va
// caricato una volta con `loadModule()` prima del primo uso.
import libpg from 'libpg-query';

const { loadModule, parse } = libpg;
await loadModule();

// `URL.pathname` non è un percorso di file: su Windows restituisce
// `/C:/...` e lascia gli spazi codificati (`%20`), quindi `join` non
// trovava niente e il controllo passava a vuoto. `fileURLToPath` fa la
// conversione giusta su tutti i sistemi.
const ROOT = fileURLToPath(new URL('..', import.meta.url));
const DIRS = ['migrations', 'supabase/migrations', 'supabase'];

async function sqlFiles(dir) {
  let entries;
  try {
    entries = await readdir(join(ROOT, dir), { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((e) => e.isFile() && e.name.endsWith('.sql'))
    .map((e) => join(ROOT, dir, e.name));
}

const files = (await Promise.all(DIRS.map(sqlFiles))).flat().sort();
if (files.length === 0) {
  console.error('Nessun file .sql trovato: controllare i percorsi in DIRS.');
  process.exit(1);
}

const failures = [];
for (const file of files) {
  const name = relative(ROOT, file).replace(/\\/g, '/');
  try {
    await parse(await readFile(file, 'utf8'));
    console.log(`  ok   ${name}`);
  } catch (error) {
    failures.push({ name, message: error?.message ?? String(error) });
    console.log(`  NO   ${name}`);
  }
}

console.log(`\n${files.length - failures.length}/${files.length} file analizzati senza errori.`);
if (failures.length > 0) {
  console.error('\nErrori di sintassi:');
  for (const f of failures) console.error(`\n${f.name}\n  ${f.message}`);
  process.exit(1);
}
