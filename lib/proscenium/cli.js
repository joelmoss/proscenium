import { writeAll } from 'std/streams/mod.ts'
import { parseArgs } from './cli/utils.js'

import javascriptBuilder from './cli/builders/javascript.js'
import reactBuilder from './cli/builders/react.js'
import solidBuilder from './cli/builders/solid.js'

const builders = {
  javascript: javascriptBuilder,
  react: reactBuilder,
  solid: solidBuilder
}

if (import.meta.main) {
  await writeAll(Deno.stdout, await main(Deno.args))
}

async function main(args = []) {
  const [cwd, entrypoint, builderName] = parseArgs(args)
  return await builders[builderName](cwd, entrypoint)
}

export default main
