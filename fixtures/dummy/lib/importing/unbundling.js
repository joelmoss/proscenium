import "./app/one.js" with { unbundle: 'true' }
import "unbundle:./app/two.js";
import "three.js"; // unbundled from import map