/**
 * @param {string} string
 * @param {URL} [baseURL]
 * @returns {URL | undefined}
 */
export function tryURLParse(string, baseURL) {
  try {
    return new URL(string, baseURL)
  } catch (e) {
    return undefined
  }
}

/**
 * @param {string} specifier
 * @param {URL} baseURL
 * @returns {URL | undefined}
 */
export function tryURLLikeSpecifierParse(specifier, baseURL) {
  if (specifier.startsWith('/') || specifier.startsWith('./') || specifier.startsWith('../')) {
    return tryURLParse(specifier, baseURL)
  }

  return tryURLParse(specifier)
}
