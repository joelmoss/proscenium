// Recursively Scans the /app path for any JS/JSX/CSS files, and compiles each one, while also
// building a manifest (JSON) of all files that are built. The manifest contains a simple mapping of
// source file => compiled file. The compiled files are appended with the content digest, for
// caching.

import { writeAll } from 'std/streams/mod.ts'
import { MuxAsyncIterator } from 'std/async/mod.ts'
import { expandGlob, ensureDir } from 'std/fs/mod.ts'
import { extname, relative, join, dirname, parse } from 'std/path/mod.ts'

import build from './cli.js'

const extnameToBuilderMap = {
  '.js': 'javascript'
}

async function main(args = []) {
  const [root, ...paths] = args
  const outDir = join(root, 'public', 'assets')
  const manifest = {}
  const promises = []
  const mux = new MuxAsyncIterator()

  paths.forEach(path => {
    mux.add(expandGlob(`${path}/**/*.{css,js,jsx}`, { root }))
  })

  for await (const file of mux) {
    const builder = extnameToBuilderMap[extname(file.path)]

    if (!builder) {
      console.error('--! Failed to compile %o (unknown builder)', relative(root, file.path))
      continue
    }

    promises.push(
      compile({ ...file, root, outDir }).then(({ inPath, outPath }) => {
        manifest[inPath] = outPath
      })
    )
  }

  await Promise.allSettled(promises)

  return new TextEncoder().encode(JSON.stringify(manifest))
}

function compile({ root, path, outDir }) {
  const entrypoint = relative(root, path)
  const { dir, name, ext } = parse(entrypoint)
  const builder = extnameToBuilderMap[ext]

  console.log('--- Compiling %o with %s builder...', entrypoint, builder)

  return build([root, entrypoint, builder])
    .then(src => {
      console.log(2)
      return digest(src)
    })
    .then(({ hash, source }) => {
      const path = join(outDir, dir, `${name}-${hash}${ext}`)

      return ensureDir(dirname(path))
        .then(() => Deno.writeTextFile(path, new TextDecoder().decode(source)))
        .then(() => ({ inPath: entrypoint, outPath: relative(outDir, path) }))
    })
}

async function digest(source) {
  const view = new DataView(await crypto.subtle.digest('SHA-1', source))

  let hash = ''
  for (let index = 0; index < view.byteLength; index += 4) {
    hash += view.getUint32(index).toString(16).padStart(8, '0')
  }

  return { hash, source }
}

export default main

if (import.meta.main) {
  await writeAll(Deno.stdout, await main(Deno.args))
}
