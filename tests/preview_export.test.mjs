import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('copy export loads Mermaid SVG from a data URL', async () => {
  let copyHandler;
  let imageSource;

  const copyButton = {
    addEventListener(event, handler) {
      if (event === 'click') copyHandler = handler;
    },
  };
  const container = {
    innerHTML: '',
    querySelector() {
      return null;
    },
  };

  globalThis.window = {
    rendererReady: true,
    mermaid: {
      async render() {
        return {
          svg: '<svg viewBox="0 0 100 50"><foreignObject><div xmlns="http://www.w3.org/1999/xhtml">Label</div></foreignObject></svg>',
        };
      },
    },
  };
  globalThis.document = {
    body: { dataset: {} },
    getElementById(id) {
      if (id === 'btn-copy') return copyButton;
      if (id === 'graph-container') return container;
      return null;
    },
  };
  globalThis.DOMParser = class {
    parseFromString() {
      return {
        documentElement: {
          hasAttribute(name) {
            return name === 'viewBox';
          },
          getAttribute(name) {
            return name === 'viewBox' ? '0 0 100 50' : null;
          },
          setAttribute() {},
        },
      };
    }
  };
  globalThis.XMLSerializer = class {
    serializeToString() {
      return '<svg viewBox="0 0 100 50"><foreignObject><div xmlns="http://www.w3.org/1999/xhtml">Label</div></foreignObject></svg>';
    }
  };
  globalThis.Image = class {
    set src(value) {
      imageSource = value;
    }
  };

  const previewPath = new URL('../static/js/preview.js', import.meta.url);
  const source = await readFile(previewPath, 'utf8');
  const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
  const { initPreview } = await import(moduleUrl);

  initPreview('mermaid.js', 'default', 'light');
  await window.renderGraph('flowchart TD\nA --> B');
  copyHandler();

  assert.match(imageSource, /^data:image\/svg\+xml;charset=utf-8,/);
});
