import "pkg";
import imported from "./imported";
import "/lib/foo.js"; // app
import "./foo"; // extensionless
import "@rubygems/gem3/lib/gem3/console.js"; // same gem
import "@rubygems/gem1/lib/gem1/console.js"; // internal gem
import "@rubygems/gem4/lib/gem4/console.js"; // external gem
import styles from "./styles.module.css";

console.log(styles);
console.log("lib/gem3/gem3");
imported();
