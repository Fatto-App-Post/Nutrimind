// Controlla che ogni Edge Function sia TypeScript sintatticamente
// valido. Non è un controllo dei tipi: `deno check` scaricherebbe le
// dipendenze da esm.sh e deno.land e non è mai stato eseguito su questo
// codice, quindi è un passo successivo (vedi docs/PROSSIMI_PASSI.md).
// Qui si intercetta l'errore più frequente e più costoso: pubblicare una
// funzione che non parte nemmeno.
//
// Uso: npm install --no-save esbuild@0.25.0 && node scripts/check-functions.mjs

import { readdir, readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { transform } from 'esbuild';

const ROOT = new URL('..', import.meta.url).pathname;
const FUNCTIONS = join(ROOT, 'supabase/functions');

const dirs = (await readdir(FUNCTIONS, { withFileTypes: true }))
  .filter((e) => e.isDirectory() && !e.name.startsWith('_'))
  .map((e) => e.name)
  .sort();

if (dirs.length === 0) {
  console.error('Nessuna funzione trovata in supabase/functions.');
  process.exit(1);
}

const failures = [];
for (const dir of dirs) {
  const file = join(FUNCTIONS, dir, 'index.ts');
  const name = relative(ROOT, file).replace(/\\/g, '/');
  try {
    const source = await readFile(file, 'utf8');
    await transform(source, { loader: 'ts', format: 'esm', target: 'es2022' });
    console.log(`  ok   ${name}`);
  } catch (error) {
    failures.push({ name, message: error?.message ?? String(error) });
    console.log(`  NO   ${name}`);
  }
}

console.log(`\n${dirs.length - failures.length}/${dirs.length} funzioni analizzate senza errori.`);
if (failures.length > 0) {
  console.error('\nErrori:');
  for (const f of failures) console.error(`\n${f.name}\n  ${f.message}`);
  process.exit(1);
}
