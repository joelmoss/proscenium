import { parse } from 'https://deno.land/std/flags/mod.ts'
import init, { transform } from 'https://unpkg.com/@parcel/css-wasm'

export default async function (args) {
  const { _: entrypoints, ...flags } = parse(args, {
    default: {
      minify: false,
      'css-modules': false,
      'source-map': false,
      nesting: false
    }
  })

  const entrypoint = entrypoints[0]
  const contents = await Deno.readTextFile(entrypoint)

  await init()

  const result = transform({
    filename: entrypoint,
    code: new TextEncoder().encode(contents),
    minify: flags.minify,
    drafts: {
      nesting: flags.nesting
    },
    targets: {
      safari: (13 << 16) | (2 << 8)
    },
    cssModules: flags['css-modules'],
    sourceMap: flags['source-map']
  })

  // console.log(new TextDecoder().decode(code))

  return result.code
}
