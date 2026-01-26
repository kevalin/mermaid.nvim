local M = {}
local uv = vim.loop

M.port = nil
M.server = nil
M.current_content = "graph TD\nA[Loading...]"

function M.start_server()
  if M.server then return M.port end

  M.server = uv.new_tcp()
  -- Bind to localhost on a random available port (0)
  M.server:bind("127.0.0.1", 0)
  
  -- Get the assigned port
  local addr = M.server:getsockname()
  M.port = addr.port

  M.server:listen(128, function(err)
    assert(not err, err)
    local client = uv.new_tcp()
    M.server:accept(client)
    
    local data_buffer = ""

    client:read_start(function(err, chunk)
      if err or not chunk then
        client:close()
        return
      end
      
      data_buffer = data_buffer .. chunk
      
      -- Simple HTTP parsing (very basic)
      -- We assume GET requests
      if data_buffer:match("\r\n\r\n") then
          -- Request complete
          local method, path = data_buffer:match("^(%w+)%s+(%S+)%s+HTTP")
          
          local response_body = ""
          local headers = "HTTP/1.1 200 OK\r\nConnection: close\r\n"
          
          if path == "/" or path == "/index.html" then
              response_body = M.get_html_template()
              headers = headers .. "Content-Type: text/html\r\n"
          elseif path == "/content" then
              response_body = M.current_content
              headers = headers .. "Content-Type: text/plain\r\n"
          else
              headers = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n"
              response_body = "Not Found"
          end
          
          headers = headers .. "Content-Length: " .. #response_body .. "\r\n\r\n"
          
          client:write(headers .. response_body, function()
             client:close()
          end)
      end
    end)
  end)
  
  return M.port
end

function M.stop_server()
    if M.server then
        M.server:close()
        M.server = nil
        M.port = nil
    end
end

function M.set_content(content)
    M.current_content = content
end

function M.get_html_template()
    return [[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Mermaid Live Preview</title>
  <style>
    body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; font-family: sans-serif; }
    .mermaid { width: 100%; height: 100%; display: flex; justify-content: center; align-items: center; cursor: grab; }
    .mermaid:active { cursor: grabbing; }
    #error-container { position: absolute; bottom: 0; left: 0; right: 0; background: rgba(255,0,0,0.8); color: white; padding: 10px; display: none; font-family: monospace; }
    /* Toolbar styled like typical map/zoom controls */
    #toolbar { position: absolute; bottom: 20px; left: 20px; display: flex; flex-direction: column; gap: 5px; z-index: 100; }
    #toolbar button { 
        width: 32px; height: 32px; 
        background: white; border: 1px solid #ccc; border-radius: 4px; 
        cursor: pointer; padding: 5px; 
        display: flex; justify-content: center; align-items: center; 
        box-shadow: 0 1px 3px rgba(0,0,0,0.2); 
        color: #333;
    }
    #toolbar button:hover { background: #f4f4f4; color: #000; }
    #toolbar button svg { width: 20px; height: 20px; }
  </style>
  <script src="https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js"></script>
</head>
<body>
  <div id="toolbar">
    <button id="btn-zoom-in" title="Zoom In">
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="m19.6 21l-6.3-6.3q-.75.6-1.725.95T9.5 16q-2.725 0-4.612-1.888T3 9.5t1.888-4.612T9.5 3t4.613 1.888T16 9.5q0 1.1-.35 2.075T14.7 13.3l6.3 6.3zM9.5 14q1.875 0 3.188-1.312T14 9.5t-1.312-3.187T9.5 5T6.313 6.313T5 9.5t1.313 3.188T9.5 14m-1-1.5v-2h-2v-2h2v-2h2v2h2v2h-2v2z"/></svg>
    </button>
    <button id="btn-zoom-out" title="Zoom Out">
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="m19.6 21l-6.3-6.3q-.75.6-1.725.95T9.5 16q-2.725 0-4.612-1.888T3 9.5t1.888-4.612T9.5 3t4.613 1.888T16 9.5q0 1.1-.35 2.075T14.7 13.3l6.3 6.3zM9.5 14q1.875 0 3.188-1.312T14 9.5t-1.312-3.187T9.5 5T6.313 6.313T5 9.5t1.313 3.188T9.5 14M7 10.5v-2h5v2z"/></svg>
    </button>
    <button id="btn-reset" title="Reset View">
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 20q-3.35 0-5.675-2.325T4 12t2.325-5.675T12 4q1.725 0 3.3.712T18 6.75V4h2v7h-7V9h4.2q-.8-1.4-2.187-2.2T12 6Q9.5 6 7.75 7.75T6 12t1.75 4.25T12 18q1.925 0 3.475-1.1T17.65 14h2.1q-.7 2.65-2.85 4.325T12 20"/></svg>
    </button>
    <div style="height: 1px; background: #ccc; margin: 2px 0;"></div>
    <button id="btn-copy" title="Copy Image (PNG)">
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 18q-.825 0-1.412-.587T7 16V4q0-.825.588-1.412T9 2h9q.825 0 1.413.588T20 4v12q0 .825-.587 1.413T18 18zm-4 4q-.825 0-1.412-.587T3 20V6h2v14h11v2z"/></svg>
    </button>
    <button id="btn-download" title="Download SVG">
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="m12 16l-5-5l1.4-1.45l2.6 2.6V4h2v8.15l2.6-2.6L17 11zm-6 4q-.825 0-1.412-.587T4 18v-3h2v3h12v-3h2v3q0 .825-.587 1.413T18 20z"/></svg>
    </button>
  </div>
  <div class="mermaid" id="graph-container"></div>
  <div id="error-container"></div>
  
  <script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
    mermaid.initialize({ startOnLoad: false });
    
    let lastContent = "";
    let currentSVGCode = ""; // Store raw SVG for copying
    let panZoomInstance = null;
    let panState = null;

    // --- Button Logic ---

    // Zoom Controls
    document.getElementById('btn-zoom-in').addEventListener('click', () => {
        if (panZoomInstance) panZoomInstance.zoomIn();
    });
    document.getElementById('btn-zoom-out').addEventListener('click', () => {
        if (panZoomInstance) panZoomInstance.zoomOut();
    });
    document.getElementById('btn-reset').addEventListener('click', () => {
        if (panZoomInstance) {
            panZoomInstance.resetZoom();
            panZoomInstance.resetPan();
        }
    });

    // Convert SVG string to PNG Blob and copy to clipboard
    document.getElementById('btn-copy').addEventListener('click', () => {
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
        const svgBlob = new Blob([highResSVG], {type: "image/svg+xml;charset=utf-8"});
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

    document.getElementById('btn-download').addEventListener('click', () => {
        // Use currentSVGCode for pure download as well
        if (!currentSVGCode) return;

        const blob = new Blob([currentSVGCode], {type: "image/svg+xml;charset=utf-8"});
        const url = URL.createObjectURL(blob);
        
        const a = document.createElement('a');
        a.href = url;
        a.download = "mermaid-diagram.svg";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    });

    async function renderGraph(content) {
        if (content === lastContent) return;
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
            errorContainer.style.display = 'none';

            // Check if content is empty
            if (!content.trim()) return;

            const { svg } = await mermaid.render('mermaid-svg', content);
            currentSVGCode = svg; // Cache the clean SVG
            container.innerHTML = svg;
            
            const svgEl = container.querySelector('svg');
            if (svgEl) {
                svgEl.style.cssText = "";
                svgEl.style.width = "100%";
                svgEl.style.height = "100%";
                
                panZoomInstance = svgPanZoom(svgEl, {
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
            errorContainer.textContent = e.toString();
            errorContainer.style.display = 'block';
        }
    }

    async function poll() {
        try {
            const res = await fetch('/content');
            const uniqueId = res.headers.get("X-Unique-ID");
            const text = await res.text();
            await renderGraph(text);
        } catch (e) {
            console.error("Polling error", e);
        }
        setTimeout(poll, 1000);
    }
    
    poll();
  </script>
</body>
</html>
]]
end

return M
