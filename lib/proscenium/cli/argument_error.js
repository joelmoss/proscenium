export default class CliArgumentError extends Error {
  static MESSAGES = {
    cwdRequired: 'Current working directory is required as first argument.',
    entrypointRequired: 'An entry point is required as second argument.',
    builderRequired: 'The builder is required as third and final argument.',

    cwdUnknown: ({ cwd }) => `A valid working directory is required - received ${cwd}`,
    entrypointUnknown: ({ entrypoint }) =>
      `A valid entrypoint is required - received ${entrypoint}`,
    builderUnknown: ({ builder }) => `Unknown builder '${builder}'`
  }

  constructor(reason, options) {
    let message = CliArgumentError.MESSAGES[reason]
    if (typeof message === 'function') {
      message = message(options)
    }

    super(message, options)

    this.reason = reason
    this.message = message
  }
}
