import { writeAll } from 'https://deno.land/std/streams/conversion.ts'
import builder from './builder.js'

const [cwd, entrypoint] = Deno.args
const result = await builder(cwd, entrypoint)

await writeAll(Deno.stdout, result.outputFiles[0].contents)
