import { writeAll } from 'streams'
import { join } from 'path'

import CliArgumentError from './cli/argument_error.js'
import jsxBuilder from './cli/builders/jsx.js'

export const builders = {
  jsx: jsxBuilder
}

if (import.meta.main) {
  await writeAll(Deno.stdout, await main(Deno.args))
}

async function main(args = []) {
  const [cwd, entrypoint, builder] = parseArgs(args)

  return await builders[builder](cwd, entrypoint)
}

export default main

function parseArgs(args) {
  const [cwd, entrypoint, builder] = args

  if (!cwd) {
    throw new CliArgumentError('cwdRequired')
  }

  if (!entrypoint) {
    throw new CliArgumentError('entrypointRequired')
  }

  if (!builder) {
    throw new CliArgumentError('builderRequired')
  }

  try {
    const stat = Deno.lstatSync(cwd)
    if (!stat.isDirectory) {
      throw new CliArgumentError(
        `Current working directory is required as the first argument - received ${cwd}`
      )
    }
  } catch {
    throw new CliArgumentError('cwdUnknown', { cwd })
  }

  try {
    const stat = Deno.lstatSync(join(cwd, entrypoint))
    if (!stat.isFile) {
      throw new CliArgumentError(
        `Entrypoint is required as the second argument - received ${entrypoint}`
      )
    }
  } catch {
    throw new CliArgumentError('entrypointUnknown', { entrypoint })
  }

  const builderKeys = Object.keys(builders)
  if (!builderKeys.includes(builder)) {
    throw new CliArgumentError('builderUnknown', { builder })
  }

  return args
}
