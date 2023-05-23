import init from "@proscenium/component-manager";

init({
  debug: true,
  buildComponentPath(component) {
    return `${component}.jsx`;
  },
});

console.log("app/views/layouts/application.js");
