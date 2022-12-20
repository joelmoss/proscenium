import { tryURLLikeSpecifierParse, tryURLParse } from './utils.js'

/**
 * @param {string} specifier
 * @param {ParsedImportMap} parsedImportMap
 * @param {URL} scriptURL
 * @returns {{ resolvedImport: URL | null, matched: boolean }}
 */
export function resolvePath(specifier, parsedImportMap, scriptURL) {
  const asURL = tryURLLikeSpecifierParse(specifier, scriptURL)
  const normalizedSpecifier = asURL ? asURL.href : specifier
  const scriptURLString = scriptURL.href

  for (const [scopePrefix, scopeImports] of Object.entries(parsedImportMap.scopes || {})) {
    if (
      scopePrefix === scriptURLString ||
      (scopePrefix.endsWith('/') && scriptURLString.startsWith(scopePrefix))
    ) {
      const scopeImportsMatch = resolveImportsMatch(normalizedSpecifier, scopeImports)

      if (scopeImportsMatch) {
        return { resolvedImport: scopeImportsMatch, matched: true }
      }
    }
  }

  const topLevelImportsMatch = resolveImportsMatch(
    normalizedSpecifier,
    parsedImportMap.imports || {}
  )

  if (topLevelImportsMatch) {
    return { resolvedImport: topLevelImportsMatch, matched: true }
  }

  // The specifier was able to be turned into a URL, but wasn't remapped into anything.
  if (asURL) {
    return { resolvedImport: asURL, matched: false }
  }

  return { resolvedImport: null, matched: false }
}

/**
 * @param {string} normalizedSpecifier
 * @param {ParsedSpecifierMap} specifierMap
 */
function resolveImportsMatch(normalizedSpecifier, specifierMap) {
  for (const [specifierKey, resolutionResult] of Object.entries(specifierMap)) {
    // Exact-match case
    if (specifierKey === normalizedSpecifier) {
      if (!resolutionResult) {
        throw new TypeError(`Blocked by a null entry for "${specifierKey}"`)
      }

      if (!(resolutionResult instanceof URL)) {
        // Support aliases.
        // throw new TypeError(`Expected ${resolutionResult} to be a URL.`)
      }

      return resolutionResult
    }

    // Package prefix-match case
    if (specifierKey.endsWith('/') && normalizedSpecifier.startsWith(specifierKey)) {
      if (!resolutionResult) {
        throw new TypeError(`Blocked by a null entry for "${specifierKey}"`)
      }

      if (!(resolutionResult instanceof URL)) {
        throw new TypeError(`Expected ${resolutionResult} to be a URL.`)
      }

      const afterPrefix = normalizedSpecifier.substring(specifierKey.length)

      // Enforced by parsing
      if (!resolutionResult.href.endsWith('/')) {
        throw new TypeError(`Expected ${resolutionResult.href} to end with a '/'.`)
      }

      const url = tryURLParse(afterPrefix, resolutionResult)
      if (!url) {
        throw new TypeError(`Failed to resolve prefix-match relative URL for "${specifierKey}"`)
      }

      if (!(url instanceof URL)) {
        throw new TypeError(`Expected ${url} to be a URL.`)
      }

      return url
    }
  }

  return undefined
}
