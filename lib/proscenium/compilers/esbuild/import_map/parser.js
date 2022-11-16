import { tryURLParse, tryURLLikeSpecifierParse } from './utils.js'

/**
 * @param {ImportMap} input
 * @param {URL} baseURL
 * @returns {ParsedImportMap}
 */
export function parse(input, baseURL) {
  if (!isJSONObject(input)) {
    throw new TypeError('Import map JSON must be an object.')
  }

  if (!(baseURL instanceof URL)) {
    throw new TypeError('Missing base URL or base URL is not a URL')
  }

  let sortedAndNormalizedImports = {}
  if ('imports' in input) {
    if (!input.imports || !isJSONObject(input.imports)) {
      throw new TypeError("Import map's imports value must be an object.")
    }
    sortedAndNormalizedImports = sortAndNormalizeSpecifierMap(input.imports, baseURL)
  }

  let sortedAndNormalizedScopes = {}
  if ('scopes' in input) {
    if (!input.scopes || !isJSONObject(input.scopes)) {
      throw new TypeError("Import map's scopes value must be an object.")
    }
    sortedAndNormalizedScopes = sortAndNormalizeScopes(input.scopes, baseURL)
  }

  const badTopLevelKeys = new Set(Object.keys(input))
  badTopLevelKeys.delete('imports')
  badTopLevelKeys.delete('scopes')

  for (const badKey of badTopLevelKeys) {
    throw new TypeError(
      `Invalid top-level key "${badKey}". Only "imports" and "scopes" can be present.`
    )
  }

  // Always have these two keys, and exactly these two keys, in the result.
  return {
    imports: sortedAndNormalizedImports,
    scopes: sortedAndNormalizedScopes
  }
}

/**
 * @param {string} input
 * @param {URL} baseURL
 * @returns {ParsedImportMap}
 */
export function parseFromString(input, baseURL) {
  const importMap = JSON.parse(input)
  return parse(importMap, baseURL)
}

/**
 * @param {string} a
 * @param {string} b
 */
function codeUnitCompare(a, b) {
  if (a > b) {
    return 1
  }

  if (b > a) {
    return -1
  }

  throw new Error('This should never be reached because this is only used on JSON object keys')
}

/**
 * @param {string} specifierKey
 * @param {URL} baseURL
 * @returns {string | undefined}
 */
function normalizeSpecifierKey(specifierKey, baseURL) {
  // Ignore attempts to use the empty string as a specifier key
  if (specifierKey === '') {
    throw new TypeError(`Invalid empty string specifier key.`)
  }

  const url = tryURLLikeSpecifierParse(specifierKey, baseURL)
  if (url) return url.href

  return specifierKey
}

/**
 * @param {SpecifierMap} obj
 * @param {URL} baseURL
 * @returns {ParsedSpecifierMap}
 */
function sortAndNormalizeSpecifierMap(obj, baseURL) {
  if (!isJSONObject(obj)) {
    throw new TypeError('Expect map to be a JSON object.')
  }

  const normalized = {}

  for (const [specifierKey, value] of Object.entries(obj)) {
    const normalizedSpecifierKey = normalizeSpecifierKey(specifierKey, baseURL)
    if (!normalizedSpecifierKey) continue

    if (typeof value !== 'string') {
      throw new TypeError(
        `Invalid address ${JSON.stringify(value)} for the specifier key "${specifierKey}". ` +
          `Addresses must be strings.`
      )
    }

    const addressURL = tryURLLikeSpecifierParse(value, baseURL)
    if (!addressURL) {
      // Support aliases.
      // console.warn(`Invalid address "${value}" for the specifier key "${specifierKey}".`)
      normalized[normalizedSpecifierKey] = value
      continue
    }

    if (specifierKey.endsWith('/') && !addressURL.href.endsWith('/')) {
      throw new TypeError(
        `Invalid address "${addressURL.href}" for package specifier key "${specifierKey}". ` +
          `Package addresses must end with "/".`
      )
    }

    normalized[normalizedSpecifierKey] = addressURL
  }

  const sortedAndNormalized = {}
  const sortedKeys = Object.keys(normalized).sort((a, b) => codeUnitCompare(b, a))
  for (const key of sortedKeys) {
    sortedAndNormalized[key] = normalized[key]
  }

  return sortedAndNormalized
}

/**
 * @param {ScopesMap} obj
 * @param {URL} baseURL
 */
function sortAndNormalizeScopes(obj, baseURL) {
  const normalized = {}
  for (const [scopePrefix, potentialSpecifierMap] of Object.entries(obj)) {
    if (!isJSONObject(potentialSpecifierMap)) {
      throw new TypeError(`The value for the "${scopePrefix}" scope prefix must be an object.`)
    }

    const scopePrefixURL = tryURLParse(scopePrefix, baseURL)
    if (!scopePrefixURL) {
      throw new TypeError(`Invalid scope "${scopePrefix}" (parsed against base URL "${baseURL}").`)
    }

    const normalizedScopePrefix = scopePrefixURL.href
    normalized[normalizedScopePrefix] = sortAndNormalizeSpecifierMap(potentialSpecifierMap, baseURL)
  }

  const sortedAndNormalized = {}
  const sortedKeys = Object.keys(normalized).sort((a, b) => codeUnitCompare(b, a))
  for (const key of sortedKeys) {
    sortedAndNormalized[key] = normalized[key]
  }

  return sortedAndNormalized
}

/**
 * @param {*} value
 * @returns {value is object}
 */
function isJSONObject(value) {
  return typeof value === 'object' && value != null && !Array.isArray(value)
}
