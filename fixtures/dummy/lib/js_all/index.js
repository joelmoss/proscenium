/* absolute import */
import "/lib/js_all/one.js";

/* absolute import without extension */
import "/lib/js_all/two";

/* absolute import without filename */
import "/lib/js_all/nest";

/* relative import */
import "./three.js";

/* relative import without extension */
import "./four";

/* relative import without filename */
import "./nest2";

import "https://proscenium.test/foo.js";

/* link:* external package */
import 'pnpm-link-ext/one.js';
import 'pnpm-link-ext/two';
import 'pnpm-link-ext/nest';

// RJS
import "/constants.rjs";

// unbundle:*
import "./five.js" with { unbundle: 'true' }
import "unbundle:./six.js";
import "seven.js"; // unbundled from import map

// ENV vars
console.log(proscenium.env.RAILS_ENV + process.env.NODE_ENV);
console.log(proscenium.env.UNKNOWN);
