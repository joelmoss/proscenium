import { writeAll } from 'std/streams/mod.ts'
import { parseArgs } from './utils.js'

import builder from './builders/solid.js'

if (import.meta.main) {
  await writeAll(Deno.stdout, await main(Deno.args))
}

async function main(args = []) {
  const [cwd, entrypoint, _] = parseArgs(args)
  return await builder(cwd, entrypoint)
}

export default main
