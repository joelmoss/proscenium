import { one } from "mypackage/treeshake";
import imported from "./imported";
import "/lib/foo.js"; // app
import "./foo";
import "/gem3/lib/gem3/console.js";
import styles from "./styles.module.css";

console.log(styles);
console.log("gem3");
imported();
one();
