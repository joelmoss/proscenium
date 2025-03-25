import "pkg";
import imported from "./imported";
import "/lib/foo.js"; // app
import "./foo";
import "@rubygems/gem4/lib/gem4/console.js"; // same gem
import "@rubygems/gem3/lib/gem3/console.js"; // internal gem
import "@rubygems/gem2/lib/gem2/console.js"; // external gem
import styles from "./styles.module.css";

console.log(styles);
console.log("lib/gem4/gem4");
imported();
