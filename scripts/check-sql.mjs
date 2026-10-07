// Analizza ogni file .sql del repository con il parser di PostgreSQL.
// Non esegue niente: controlla solo che la sintassi sia valida, così un
// errore di battitura si vede in CI e non nel SQL Editor, dove il primo
// errore annulla tutto lo script.
//
// Uso: npm install --no-save libpg-query@17 && node scripts/check-sql.mjs

import { readdir, readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { parseQuery } from 'libpg-query';

const ROOT = new URL('..', import.meta.url).pathname;
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
    await parseQuery(await readFile(file, 'utf8'));
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
