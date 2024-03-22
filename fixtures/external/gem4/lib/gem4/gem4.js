import { one } from "mypackage/treeshake";
import imported from "./imported";
import "/lib/foo.js"; // app
import styles from "./styles.module.css";

console.log(styles);
console.log("gem4");
imported();
one();
