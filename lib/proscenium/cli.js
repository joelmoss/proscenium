import { writeAll } from 'std/streams/mod.ts'
import { join } from 'std/path/mod.ts'

import CliArgumentError from './cli/argument_error.js'
import jsxBuilder from './cli/builders/jsx.js'
import esbuildBuilder from './cli/builders/esbuild.js'

export const builders = {
  jsx: jsxBuilder,
  esbuild: esbuildBuilder
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
  let [cwd, entrypoint, builder] = args

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

  if (/\.(jsx?)|(css)\.map$/.test(entrypoint)) {
    entrypoint = entrypoint.replace(/\.map$/, '')
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
