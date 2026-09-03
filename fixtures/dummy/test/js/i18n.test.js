import { expect, test } from "bun:test";
import translations from "/lib/bun_fixtures/i18n.js";

test("proscenium/i18n exports the app's merged locale files", () => {
  expect(translations.en).toBeDefined();
  expect(translations.en.firstName).toBe("Joel");
});
