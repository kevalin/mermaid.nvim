let lastContent = "";
let currentSVGCode = ""; // Store raw SVG for copying
let panZoomInstance = null;
let panState = null;
let pendingContent = null;

export function initPreview(renderer, theme) {
    window.RENDERER = renderer;
    window.THEME = theme;

    // --- Button Logic ---

    // Zoom Controls
    document.getElementById('btn-zoom-in')?.addEventListener('click', () => {
        if (panZoomInstance) panZoomInstance.zoomIn();
    });
    document.getElementById('btn-zoom-out')?.addEventListener('click', () => {
        if (panZoomInstance) panZoomInstance.zoomOut();
    });
    document.getElementById('btn-reset')?.addEventListener('click', () => {
        if (panZoomInstance) {
            panZoomInstance.resetZoom();
            panZoomInstance.resetPan();
        }
    });

    // Convert SVG string to PNG Blob and copy to clipboard
    document.getElementById('btn-copy')?.addEventListener('click', () => {
        if (!currentSVGCode) return;

        // Parse SVG to get dimensions from viewBox
        const parser = new DOMParser();
        const doc = parser.parseFromString(currentSVGCode, "image/svg+xml");
        const svgElement = doc.documentElement;

        let width = 0;
        let height = 0;

        if (svgElement.hasAttribute('viewBox')) {
            const viewBox = svgElement.getAttribute('viewBox').split(/\s+|,/).map(parseFloat);
            width = viewBox[2];
            height = viewBox[3];
        } else {
            // Fallback if no viewBox (unlikely for mermaid)
            width = parseFloat(svgElement.getAttribute('width')) || 800;
            height = parseFloat(svgElement.getAttribute('height')) || 600;
        }

        // define High-Res scale
        const scale = 3;
        const finalWidth = Math.ceil(width * scale);
        const finalHeight = Math.ceil(height * scale);

        // Force dimensions on the SVG source before creating blob
        svgElement.setAttribute('width', finalWidth);
        svgElement.setAttribute('height', finalHeight);

        const serializer = new XMLSerializer();
        const highResSVG = serializer.serializeToString(svgElement);

        const img = new Image();
        const svgBlob = new Blob([highResSVG], { type: "image/svg+xml;charset=utf-8" });
        const url = URL.createObjectURL(svgBlob);

        img.onload = () => {
            const canvas = document.createElement('canvas');
            canvas.width = finalWidth;
            canvas.height = finalHeight;

            const ctx = canvas.getContext('2d');
            // Fill white background (optional, but good for PNG)
            ctx.fillStyle = 'white';
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            ctx.drawImage(img, 0, 0, finalWidth, finalHeight);

            canvas.toBlob(async (blob) => {
                try {
                    await navigator.clipboard.write([
                        new ClipboardItem({ 'image/png': blob })
                    ]);

                    const btn = document.getElementById('btn-copy');
                    btn.style.color = "green";
                    setTimeout(() => btn.style.color = "", 1000);
                } catch (err) {
                    console.error('Failed to write to clipboard', err);
                    alert('Failed to copy image to clipboard');
                }
                URL.revokeObjectURL(url);
            }, 'image/png');
        };
        img.src = url;
    });

    document.getElementById('btn-download')?.addEventListener('click', () => {
        // Use currentSVGCode for pure download as well
        if (!currentSVGCode) return;

        const blob = new Blob([currentSVGCode], { type: "image/svg+xml;charset=utf-8" });
        const url = URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = "mermaid-diagram.svg";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    });


    // Content might have arrived before initPreview
    if (window.pendingContent) {
        renderGraph(window.pendingContent);
        window.pendingContent = null;
    }
}

async function renderGraph(content) {
    if (content === lastContent) return;

    if (!window.rendererReady) {
        pendingContent = content;
        return;
    }

    lastContent = content;
    const container = document.getElementById('graph-container');
    const errorContainer = document.getElementById('error-container');

    try {
        // Save pan/zoom state if exists
        if (panZoomInstance) {
            panState = {
                zoom: panZoomInstance.getZoom(),
                pan: panZoomInstance.getPan()
            };
            panZoomInstance.destroy();
            panZoomInstance = null;
        }

        container.innerHTML = "";
        if (errorContainer) errorContainer.style.display = 'none';

        // Check if content is empty
        if (!content.trim()) return;

        let res;
        if (window.RENDERER === "beautiful-mermaid") {
            let themeObj = (window.BEAUTIFUL_THEMES && window.BEAUTIFUL_THEMES[window.THEME]);
            if (!themeObj && window.THEME === 'default') {
                themeObj = window.BEAUTIFUL_DEFAULTS;
            }
            if (!themeObj) {
                themeObj = (window.BEAUTIFUL_THEMES && window.BEAUTIFUL_THEMES['zinc-light']) || {};
            }
            res = window.renderMermaidSVG(content, { ...themeObj });
        } else {
            res = await window.mermaid.render('mermaid-svg', content);
        }
        const svg = typeof res === 'string' ? res : res.svg;

        currentSVGCode = svg; // Cache the clean SVG
        container.innerHTML = svg;

        const svgEl = container.querySelector('svg');
        if (svgEl) {
            // Remove absolute dimensions and max-constraints to allow fill
            svgEl.removeAttribute('width');
            svgEl.removeAttribute('height');
            svgEl.style.maxWidth = "100%";
            svgEl.style.maxHeight = "100%";
            svgEl.style.width = "100%";
            svgEl.style.height = "100%";

            panZoomInstance = window.svgPanZoom(svgEl, {
                zoomEnabled: true,
                controlIconsEnabled: false, // Disable default icons
                fit: true,
                center: true,
                minZoom: 0.1,
                maxZoom: 10
            });

            // Restore state if available
            if (panState) {
                panZoomInstance.zoom(panState.zoom);
                panZoomInstance.pan(panState.pan);
            }
        }
    } catch (e) {
        console.error(e);
        if (errorContainer) {
            errorContainer.textContent = e.toString();
            errorContainer.style.display = 'block';
        }
    }
}

// Global for ESM access
window.renderGraph = renderGraph;


// Expose rendererReady property
let _rendererReady = window.rendererReady === true;
Object.defineProperty(window, 'rendererReady', {
    get: () => _rendererReady,
    set: (val) => {
        _rendererReady = val;
        if (_rendererReady && pendingContent) {
            renderGraph(pendingContent);
            pendingContent = null;
        }
    }
});

if (_rendererReady && window.pendingContent) {
    renderGraph(window.pendingContent);
    window.pendingContent = null;
}
