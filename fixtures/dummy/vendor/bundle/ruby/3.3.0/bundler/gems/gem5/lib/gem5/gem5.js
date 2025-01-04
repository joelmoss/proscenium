import { one } from "mypackage/treeshake";
import imported from "./imported";
import "/lib/foo.js"; // app
import "./foo";
import "/gem5/lib/gem5/console.js";
import styles from "./styles.module.css";

console.log(styles);
console.log("gem5");
imported();
one();
