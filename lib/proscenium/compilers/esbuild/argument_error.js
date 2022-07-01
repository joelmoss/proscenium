export default class ArgumentError extends Error {
  static MESSAGES = {
    rootRequired: 'Current working directory is required as --root.',
    pathsRequired: 'One or more file paths or globs are required.',

    rootUnknown: ({ root }) => `A valid working directory is required - received ${root}`
  }

  constructor(reason, options) {
    let message = ArgumentError.MESSAGES[reason]
    if (typeof message === 'function') {
      message = message(options)
    }

    message = `${reason}: ${message}`

    super(message, options)

    this.reason = reason
    this.message = message
  }
}
