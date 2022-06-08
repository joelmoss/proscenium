import cli from '../cli.js'

Deno.bench('react', async () => {
  await cli(Deno.args)
})
