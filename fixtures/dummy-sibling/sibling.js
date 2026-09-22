// Deliberately outside the app root, in a directory whose name begins with the root's own name.
// See test/dirname_boundary_test.go. `__filename` is referenced so the constant the dirname
// plugin prepends survives into the bundle - an unused one is tree-shaken away, and the test can
// then see nothing either way.
export const siblingFilename = typeof __filename === 'undefined' ? 'undefined' : __filename
