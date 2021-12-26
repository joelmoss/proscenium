export const isTest = () => Deno.env.get('ENVIRONMENT') === 'test'

export const debug = (...args) => {
  isTest() && console.log(...args)
}
