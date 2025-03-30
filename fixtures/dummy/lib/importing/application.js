/* absolute import */
import "/lib/importing/app/one.js";

/* absolute import without extension */
import "/lib/importing/app/two";

/* absolute import without filename */
import "/lib/importing/app";

/* relative import */
import "./app/three.js";

/* relative import without extension */
import "./app/four";

/* relative import without filename */
import "./app/five";

import "..";
import ".";
