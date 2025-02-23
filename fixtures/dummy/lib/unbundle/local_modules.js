import "/lib/unbundle/foo1.js" with { unbundle: 'true' }
import "unbundle:./foo2.js";
import "/lib/foo3.js";
import { one } from "unbundle:mypackage/treeshake";
import "mypackage";
