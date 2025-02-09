export default async () => {
  window.Proscenium = window.Proscenium || {};

  if (!window.Proscenium.UJS) {
    const classPath = "/proscenium/ujs/class.js";
    const module = await import(classPath);
    window.Proscenium.UJS = new module.default();
  }
};
