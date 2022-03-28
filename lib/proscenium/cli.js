import { writeAll } from 'https://deno.land/std@0.129.0/streams/conversion.ts'
import buildJS from './cli/js_builder.js'

if (import.meta.main) {
  await writeAll(Deno.stdout, await init(Deno.args))
}

export async function init(args, options = {}) {
  return await buildJS(args, options)
}
