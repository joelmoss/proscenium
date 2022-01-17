import buildJS from './cli/js_builder.js'

if (import.meta.main) {
  await Deno.stdout.write(await init(Deno.args))
}

export async function init(args) {
  return await buildJS(args)
}
