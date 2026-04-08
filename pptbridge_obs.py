"""
PPTBridge for OBS — v2.3.0
Author  : Srđan Kotarlić
License : MIT

OBS Python script that turns a PowerPoint .pptx into:
  - /slide     clean program view for the audience
  - /presenter presenter view with notes and next slide
  - /booth     production control page
  - /          control dashboard with slide thumbnails and URLs

This MVP intentionally uses OBS Browser Sources instead of a native custom
source type. That keeps the workflow portable, easier to install, and much
faster to ship as a public project.
"""

import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import xml.etree.ElementTree as ET
import zipfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import obspython as obs

try:
    from http.server import ThreadingHTTPServer
except ImportError:
    ThreadingHTTPServer = HTTPServer


VERSION = "2.3.0"
AUTHOR = "Srđan Kotarlić"


def _initial_state():
    return {
        "loaded": False,
        "loading": False,
        "last_error": "",
        "pptx_name": "",
        "current_index": 0,
        "total_slides": 0,
        "has_next": False,
        "has_prev": False,
        "current_title": "",
        "next_title": "",
        "current_notes": "",
        "next_notes": "",
        "black_screen": False,
        "allow_lan_control": True,
        "remote_token_enabled": False,
        "local_root": "",
        "lan_root": "",
        "slide_url_local": "",
        "presenter_url_local": "",
        "booth_url_local": "",
        "control_url_local": "",
        "slide_url_lan": "",
        "presenter_url_lan": "",
        "booth_url_lan": "",
        "control_url_lan": "",
    }


_state = _initial_state()
_state_lock = threading.RLock()

_slides_dir = None
_notes = []
_titles = []
_total = 0
_pptx_path = ""
_port = 8765
_dpi = 200
_allow_lan_control = True
_remote_token = ""

_server = None
_server_thread = None

_hk_next = obs.OBS_INVALID_HOTKEY_ID
_hk_prev = obs.OBS_INVALID_HOTKEY_ID
_hk_black = obs.OBS_INVALID_HOTKEY_ID


def _find_binary(candidates):
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    return None


def _find_on_path(binary_name):
    try:
        result = subprocess.run(
            ["which", binary_name],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception:
        return None

    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return None


def _find_libreoffice():
    return _find_binary(
        [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice",
        ]
    ) or _find_on_path("soffice")


def _find_pdftoppm():
    return _find_binary(
        [
            "/opt/homebrew/bin/pdftoppm",
            "/usr/local/bin/pdftoppm",
        ]
    ) or _find_on_path("pdftoppm")


_lo_path = _find_libreoffice()
_pdftoppm_path = _find_pdftoppm()


_NSMAP = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
}


def _extract_notes_and_titles(pptx_path):
    notes_list = []
    titles_list = []

    try:
        with zipfile.ZipFile(pptx_path, "r") as archive:
            slide_files = sorted(
                (
                    name
                    for name in archive.namelist()
                    if name.startswith("ppt/slides/slide") and name.endswith(".xml")
                ),
                key=lambda value: int("".join(filter(str.isdigit, Path(value).stem)) or "0"),
            )

            for slide_file in slide_files:
                title_text = ""
                try:
                    tree = ET.fromstring(archive.read(slide_file))
                    for shape in tree.iter(f"{{{_NSMAP['p']}}}sp"):
                        nv_sp_pr = shape.find(f"{{{_NSMAP['p']}}}nvSpPr")
                        if nv_sp_pr is None:
                            continue
                        nv_pr = nv_sp_pr.find(f"{{{_NSMAP['p']}}}nvPr")
                        if nv_pr is None:
                            continue
                        placeholder = nv_pr.find(f"{{{_NSMAP['p']}}}ph")
                        if placeholder is None:
                            continue
                        if placeholder.get("type", "") not in ("title", "ctrTitle"):
                            continue

                        parts = []
                        for text_node in shape.iter(f"{{{_NSMAP['a']}}}t"):
                            if text_node.text:
                                parts.append(text_node.text)
                        title_text = " ".join(parts).strip()
                        break
                except Exception:
                    pass
                titles_list.append(title_text)

                notes_text = ""
                slide_number = "".join(filter(str.isdigit, Path(slide_file).stem))
                notes_file = f"ppt/notesSlides/notesSlide{slide_number}.xml"
                try:
                    if notes_file in archive.namelist():
                        notes_tree = ET.fromstring(archive.read(notes_file))
                        paragraphs = []
                        for shape in notes_tree.iter(f"{{{_NSMAP['p']}}}sp"):
                            nv_sp_pr = shape.find(f"{{{_NSMAP['p']}}}nvSpPr")
                            if nv_sp_pr is None:
                                continue
                            nv_pr = nv_sp_pr.find(f"{{{_NSMAP['p']}}}nvPr")
                            if nv_pr is None:
                                continue
                            placeholder = nv_pr.find(f"{{{_NSMAP['p']}}}ph")
                            if placeholder is None or placeholder.get("type", "") != "body":
                                continue
                            for para in shape.iter(f"{{{_NSMAP['a']}}}p"):
                                segments = []
                                for text_node in para.iter(f"{{{_NSMAP['a']}}}t"):
                                    if text_node.text:
                                        segments.append(text_node.text)
                                line = "".join(segments).strip()
                                if line:
                                    paragraphs.append(line)
                        notes_text = "\n".join(paragraphs)
                except Exception:
                    pass

                notes_list.append(notes_text)
    except Exception as exc:
        obs.script_log(obs.LOG_WARNING, f"PPTBridge: notes extraction failed: {exc}")

    return notes_list, titles_list


def _pdf_to_png_quartz(pdf_path, output_dir, dpi):
    try:
        import Quartz
        from Quartz import (
            CGBitmapContextCreate,
            CGBitmapContextCreateImage,
            CGColorSpaceCreateDeviceRGB,
            CGContextDrawPDFPage,
            CGContextFillRect,
            CGContextScaleCTM,
            CGContextSetRGBFillColor,
            CGImageDestinationAddImage,
            CGImageDestinationCreateWithURL,
            CGImageDestinationFinalize,
            CGPDFDocumentCreateWithURL,
            CGPDFDocumentGetNumberOfPages,
            CGPDFDocumentGetPage,
            CGPDFPageGetBoxRect,
            CGRectMake,
            kCGImageAlphaPremultipliedLast,
            kCGPDFMediaBox,
        )
        from CoreFoundation import CFURLCreateFromFileSystemRepresentation
    except ImportError:
        return False, "Quartz not available", 0

    try:
        pdf_bytes = pdf_path.encode("utf-8")
        pdf_url = CFURLCreateFromFileSystemRepresentation(
            None, pdf_bytes, len(pdf_bytes), False
        )
        pdf_doc = CGPDFDocumentCreateWithURL(pdf_url)
        if not pdf_doc:
            return False, "Quartz could not open PDF", 0

        page_count = CGPDFDocumentGetNumberOfPages(pdf_doc)
        scale = dpi / 72.0

        for page_index in range(1, page_count + 1):
            page = CGPDFDocumentGetPage(pdf_doc, page_index)
            rect = CGPDFPageGetBoxRect(page, kCGPDFMediaBox)
            width = int(rect.size.width * scale)
            height = int(rect.size.height * scale)

            colorspace = CGColorSpaceCreateDeviceRGB()
            context = CGBitmapContextCreate(
                None,
                width,
                height,
                8,
                width * 4,
                colorspace,
                kCGImageAlphaPremultipliedLast,
            )
            CGContextScaleCTM(context, scale, scale)
            CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0)
            CGContextFillRect(context, CGRectMake(0, 0, rect.size.width, rect.size.height))
            CGContextDrawPDFPage(context, page)

            image = CGBitmapContextCreateImage(context)
            output_path = os.path.join(output_dir, f"slide_{page_index - 1:03d}.png")
            output_bytes = output_path.encode("utf-8")
            output_url = CFURLCreateFromFileSystemRepresentation(
                None, output_bytes, len(output_bytes), False
            )
            destination = CGImageDestinationCreateWithURL(output_url, "public.png", 1, None)
            CGImageDestinationAddImage(destination, image, None)
            CGImageDestinationFinalize(destination)

        return True, f"Converted {page_count} slide(s) with Quartz", page_count
    except Exception as exc:
        return False, f"Quartz error: {exc}", 0


def _pdf_to_png_pdftoppm(pdf_path, output_dir, dpi):
    if not _pdftoppm_path:
        return False, "pdftoppm not found", 0

    try:
        prefix = str(Path(output_dir) / "slide")
        result = subprocess.run(
            [_pdftoppm_path, "-png", "-r", str(dpi), pdf_path, prefix],
            capture_output=True,
            text=True,
            timeout=180,
        )
        if result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or "pdftoppm failed"
            return False, message, 0

        raw_files = sorted(Path(output_dir).glob("slide-*.png"))
        for index, file_path in enumerate(raw_files):
            file_path.rename(Path(output_dir) / f"slide_{index:03d}.png")
        return True, f"Converted {len(raw_files)} slide(s) with pdftoppm", len(raw_files)
    except Exception as exc:
        return False, f"pdftoppm error: {exc}", 0


def _convert_pptx(pptx_path, output_dir, dpi):
    if not _lo_path:
        return (
            False,
            "LibreOffice not found. Install LibreOffice before loading a .pptx.",
            0,
        )

    pdf_dir = tempfile.mkdtemp(prefix="pptbridge_pdf_")
    lo_profile = tempfile.mkdtemp(prefix="pptbridge_lo_")

    try:
        result = subprocess.run(
            [
                _lo_path,
                f"-env:UserInstallation={Path(lo_profile).as_uri()}",
                "--headless",
                "--nologo",
                "--nodefault",
                "--norestore",
                "--convert-to",
                "pdf",
                "--outdir",
                pdf_dir,
                pptx_path,
            ],
            capture_output=True,
            text=True,
            timeout=240,
        )

        pdf_files = sorted(Path(pdf_dir).glob("*.pdf"))
        if not pdf_files:
            detail = result.stderr.strip() or result.stdout.strip() or "No PDF generated"
            return False, f"LibreOffice conversion failed: {detail}", 0

        pdf_path = str(pdf_files[0])

        ok, message, count = _pdf_to_png_quartz(pdf_path, output_dir, dpi)
        if not ok:
            obs.script_log(obs.LOG_INFO, f"PPTBridge: Quartz unavailable ({message}), trying pdftoppm")
            ok, message, count = _pdf_to_png_pdftoppm(pdf_path, output_dir, dpi)

        if not ok:
            return False, f"PDF to PNG conversion failed: {message}", 0

        return True, f"Converted {count} slide(s)", count
    except subprocess.TimeoutExpired:
        return False, "Conversion timed out after 240 seconds", 0
    except Exception as exc:
        return False, f"Conversion error: {exc}", 0
    finally:
        shutil.rmtree(pdf_dir, ignore_errors=True)
        shutil.rmtree(lo_profile, ignore_errors=True)


def _discover_lan_ip():
    if not _allow_lan_control:
        return ""

    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("10.255.255.255", 1))
        ip = probe.getsockname()[0]
    except Exception:
        ip = ""
    finally:
        probe.close()

    if ip.startswith("127."):
        return ""
    return ip


def _tokenize(url):
    if not _remote_token:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}token={_remote_token}"


def _network_state_fragment():
    local_root = f"http://127.0.0.1:{_port}"
    lan_ip = _discover_lan_ip()
    lan_root = f"http://{lan_ip}:{_port}" if lan_ip else ""

    return {
        "allow_lan_control": _allow_lan_control,
        "remote_token_enabled": bool(_remote_token),
        "local_root": local_root,
        "lan_root": lan_root,
        "slide_url_local": _tokenize(f"{local_root}/slide"),
        "presenter_url_local": _tokenize(f"{local_root}/presenter"),
        "booth_url_local": _tokenize(f"{local_root}/booth"),
        "control_url_local": _tokenize(f"{local_root}/"),
        "slide_url_lan": _tokenize(f"{lan_root}/slide") if lan_root else "",
        "presenter_url_lan": _tokenize(f"{lan_root}/presenter") if lan_root else "",
        "booth_url_lan": _tokenize(f"{lan_root}/booth") if lan_root else "",
        "control_url_lan": _tokenize(f"{lan_root}/") if lan_root else "",
    }


def _refresh_network_state():
    with _state_lock:
        _state.update(_network_state_fragment())


def _set_loading(loading, last_error=None):
    with _state_lock:
        _state["loading"] = loading
        if last_error is not None:
            _state["last_error"] = last_error
        _state.update(_network_state_fragment())


def _update_state():
    with _state_lock:
        network_state = _network_state_fragment()
        loading = _state.get("loading", False)
        last_error = _state.get("last_error", "")
        black_screen = _state.get("black_screen", False)

        if not _slides_dir or _total <= 0:
            _state.clear()
            _state.update(_initial_state())
            _state.update(network_state)
            _state["loading"] = loading
            _state["last_error"] = last_error
            _state["black_screen"] = black_screen
            return

        current = max(0, min(_state.get("current_index", 0), _total - 1))
        next_index = current + 1

        _state.clear()
        _state.update(_initial_state())
        _state.update(network_state)
        _state.update(
            {
                "loaded": True,
                "loading": loading,
                "last_error": last_error,
                "pptx_name": Path(_pptx_path).name if _pptx_path else "",
                "current_index": current,
                "total_slides": _total,
                "has_next": next_index < _total,
                "has_prev": current > 0,
                "current_title": _titles[current] if current < len(_titles) else "",
                "next_title": _titles[next_index] if next_index < len(_titles) else "",
                "current_notes": _notes[current] if current < len(_notes) else "",
                "next_notes": _notes[next_index] if next_index < len(_notes) else "",
                "black_screen": black_screen,
            }
        )


def _state_snapshot():
    with _state_lock:
        return dict(_state)


def _current_slide_path(index):
    if not _slides_dir:
        return None
    path = Path(_slides_dir) / f"slide_{index:03d}.png"
    return str(path)


def _next_slide():
    with _state_lock:
        if _state.get("loaded") and _state["current_index"] < _state["total_slides"] - 1:
            _state["current_index"] += 1
            _update_state()
            return True
    return False


def _prev_slide():
    with _state_lock:
        if _state.get("loaded") and _state["current_index"] > 0:
            _state["current_index"] -= 1
            _update_state()
            return True
    return False


def _goto_slide(index):
    with _state_lock:
        if _state.get("loaded") and 0 <= index < _state["total_slides"]:
            _state["current_index"] = index
            _update_state()
            return True
    return False


def _toggle_black():
    with _state_lock:
        _state["black_screen"] = not _state.get("black_screen", False)
        _update_state()


def _load_pptx(path):
    global _slides_dir, _notes, _titles, _total, _pptx_path

    if not path or not os.path.exists(path):
        _set_loading(False, "PowerPoint file not found.")
        obs.script_log(obs.LOG_WARNING, f"PPTBridge: file not found: {path}")
        return False

    _set_loading(True, "")
    obs.script_log(obs.LOG_INFO, f"PPTBridge: loading {path}")

    notes, titles = _extract_notes_and_titles(path)
    new_slides_dir = tempfile.mkdtemp(prefix="pptbridge_slides_")

    ok, message, count = _convert_pptx(path, new_slides_dir, _dpi)
    if not ok:
        shutil.rmtree(new_slides_dir, ignore_errors=True)
        _set_loading(False, message)
        obs.script_log(obs.LOG_ERROR, f"PPTBridge: {message}")
        return False

    old_slides_dir = None
    with _state_lock:
        old_slides_dir = _slides_dir
        _slides_dir = new_slides_dir
        _notes = notes
        _titles = titles
        _total = count
        _pptx_path = path
        _state["current_index"] = 0
        _state["black_screen"] = False
        _state["last_error"] = ""
        _state["loading"] = False
        _update_state()

    if old_slides_dir and os.path.exists(old_slides_dir):
        shutil.rmtree(old_slides_dir, ignore_errors=True)

    obs.script_log(obs.LOG_INFO, f"PPTBridge: loaded {count} slide(s) from {Path(path).name}")
    return True


_HTML_SLIDE = """<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>PPTBridge Slide</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    html,body{width:100%;height:100%;background:#000;overflow:hidden}
    body{font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}
    #frame{width:100vw;height:100vh;display:flex;align-items:center;justify-content:center;position:relative}
    #img{max-width:100%;max-height:100%;object-fit:contain;display:none}
    #status{color:#4e5666;font-size:14px;letter-spacing:.02em}
    #black{position:fixed;inset:0;background:#000;display:none;z-index:10}
  </style>
</head>
<body>
  <div id="black"></div>
  <div id="frame">
    <div id="status">PPTBridge is waiting for a presentation…</div>
    <img id="img" alt="Slide">
  </div>
  <script>
    function withQ(path){
      const q=window.location.search;
      return q?path+(path.includes('?')?'&':'?')+q.slice(1):path;
    }
    function setStatus(text){
      document.getElementById('status').textContent=text;
      document.getElementById('status').style.display='block';
      document.getElementById('img').style.display='none';
    }
    let currentIndex=-1;
    async function poll(){
      try{
        const res=await fetch(withQ('/api/state'));
        if(!res.ok)return;
        const s=await res.json();
        document.getElementById('black').style.display=s.black_screen?'block':'none';
        if(s.loading){setStatus('Loading presentation…');return;}
        if(!s.loaded){
          setStatus(s.last_error||'PPTBridge is waiting for a presentation…');
          return;
        }
        if(s.current_index!==currentIndex){
          currentIndex=s.current_index;
          const img=document.getElementById('img');
          img.src=withQ('/api/slide/'+currentIndex+'?t='+Date.now());
          img.style.display='block';
          document.getElementById('status').style.display='none';
        }
      }catch(_err){}
    }
    setInterval(poll,250);
    poll();
  </script>
</body>
</html>
"""


_HTML_PRESENTER = """<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>PPTBridge Presenter</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    :root{
      --bg:#0c1015;
      --panel:#131920;
      --card:#181f28;
      --border:#253040;
      --accent:#e7ff5f;
      --accent-2:#5fd7ff;
      --text:#edf3fb;
      --muted:#8e9fb4;
      --danger:#ff5f6d;
    }
    html,body{width:100%;height:100%;background:linear-gradient(180deg,#0b0f13,#121821);color:var(--text);font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;overflow:hidden}
    .app{display:grid;grid-template-rows:54px 1fr 56px;height:100vh}
    .top{display:flex;align-items:center;gap:14px;padding:0 18px;background:rgba(12,16,21,.92);border-bottom:1px solid var(--border)}
    .brand{font-weight:800;letter-spacing:.02em}
    .brand span{color:var(--accent)}
    .file{flex:1;min-width:0;color:var(--muted);font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .clock{font-variant-numeric:tabular-nums;font-size:24px}
    .black{display:none;background:var(--danger);padding:6px 10px;border-radius:999px;font-size:12px;font-weight:700;letter-spacing:.08em}
    .black.on{display:inline-flex}
    .main{display:grid;grid-template-columns:minmax(0,1fr) 360px;min-height:0}
    .current{position:relative;display:flex;align-items:center;justify-content:center;background:#000}
    .current img{max-width:100%;max-height:100%;object-fit:contain;display:none}
    .placeholder{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:#415162;font-size:14px}
    .badge{position:absolute;left:16px;bottom:16px;background:rgba(0,0,0,.72);border:1px solid var(--border);border-radius:999px;padding:6px 12px;font-size:12px;color:var(--muted)}
    .badge strong{color:#fff}
    .side{display:grid;grid-template-rows:auto auto 1fr;gap:12px;padding:14px;background:rgba(19,25,32,.95);border-left:1px solid var(--border);min-height:0}
    .panel{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:14px}
    .label{font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:10px}
    .label.next{color:var(--accent-2)}
    .preview{aspect-ratio:16/9;border-radius:12px;background:#000;display:flex;align-items:center;justify-content:center;overflow:hidden}
    .preview img{width:100%;height:100%;object-fit:contain}
    .preview .empty{color:#4b5c70;font-size:13px}
    .notes{display:flex;flex-direction:column;min-height:0}
    .notesbox{flex:1;overflow:auto;font-size:18px;line-height:1.6;white-space:pre-wrap;color:var(--text)}
    .notesbox.empty{color:var(--muted);font-style:italic}
    .foot{display:flex;align-items:center;gap:14px;padding:0 18px;border-top:1px solid var(--border);background:rgba(12,16,21,.92)}
    .timer{font-variant-numeric:tabular-nums;font-size:28px;min-width:92px}
    .controls{display:flex;gap:8px}
    button{border:none;border-radius:999px;padding:8px 14px;background:var(--card);color:var(--text);font-size:13px;cursor:pointer}
    button:hover{background:#212a35}
    .progress{flex:1;height:6px;background:var(--card);border-radius:999px;overflow:hidden}
    .fill{height:100%;width:0;background:linear-gradient(90deg,var(--accent),#ffffff)}
    .count{font-size:13px;color:var(--muted);min-width:64px;text-align:right}
    .author{font-size:12px;color:var(--muted)}
    .author span{color:var(--accent)}
  </style>
</head>
<body>
  <div class="app">
    <div class="top">
      <div class="brand">PPT<span>Bridge</span></div>
      <div class="file" id="file">No presentation loaded</div>
      <div class="black" id="blackBadge">BLACK</div>
      <div class="clock" id="clock">00:00:00</div>
    </div>
    <div class="main">
      <div class="current">
        <div class="placeholder" id="placeholder">Load a .pptx in OBS Scripts</div>
        <img id="currentSlide" alt="Current slide">
        <div class="badge" id="badge" style="display:none">Slide <strong id="slideNo">1</strong> / <strong id="slideTotal">1</strong></div>
      </div>
      <div class="side">
        <div class="panel">
          <div class="label next">Next slide</div>
          <div class="preview" id="nextPreview"><div class="empty">No next slide</div></div>
        </div>
        <div class="panel">
          <div class="label">Keyboard control</div>
          <div style="color:var(--muted);font-size:13px;line-height:1.55">
            Right / Page Down / Space = next<br>
            Left / Page Up / Backspace = previous<br>
            B = black, Home = first, End = last
          </div>
        </div>
        <div class="panel notes">
          <div class="label">Presenter notes</div>
          <div class="notesbox empty" id="notes">No notes available</div>
        </div>
      </div>
    </div>
    <div class="foot">
      <div class="timer" id="timer">00:00</div>
      <div class="controls">
        <button onclick="toggleTimer()">Start / Stop</button>
        <button onclick="resetTimer()">Reset</button>
      </div>
      <div class="progress"><div class="fill" id="fill"></div></div>
      <div class="count" id="count">0 / 0</div>
      <div class="author">PPTBridge by <span>Srđan Kotarlić</span></div>
    </div>
  </div>
  <script>
    function withQ(path){
      const q=window.location.search;
      return q?path+(path.includes('?')?'&':'?')+q.slice(1):path;
    }
    async function cmd(name){
      try{await fetch(withQ('/api/cmd/'+name),{method:'POST'});}catch(_err){}
    }
    function currentTime(){
      const d=new Date();
      return d.toLocaleTimeString('en-GB',{hour12:false});
    }
    let seconds=0;
    let timerRunning=false;
    let timerId=null;
    function updateTimer(){
      const m=Math.floor(seconds/60);
      const s=seconds%60;
      document.getElementById('timer').textContent=String(m).padStart(2,'0')+':'+String(s).padStart(2,'0');
    }
    function toggleTimer(){
      if(timerRunning){
        clearInterval(timerId);
        timerRunning=false;
      }else{
        timerId=setInterval(()=>{seconds+=1;updateTimer();},1000);
        timerRunning=true;
      }
    }
    function resetTimer(){
      clearInterval(timerId);
      timerRunning=false;
      seconds=0;
      updateTimer();
    }
    setInterval(()=>{document.getElementById('clock').textContent=currentTime();},1000);
    document.getElementById('clock').textContent=currentTime();
    updateTimer();

    let currentIndex=-1;
    async function poll(){
      try{
        const res=await fetch(withQ('/api/state'));
        if(!res.ok)return;
        const s=await res.json();

        document.getElementById('file').textContent=s.pptx_name||'No presentation loaded';
        document.getElementById('blackBadge').classList.toggle('on',!!s.black_screen);

        if(s.loading){
          document.getElementById('placeholder').textContent='Loading presentation…';
          return;
        }
        if(!s.loaded){
          document.getElementById('placeholder').textContent=s.last_error||'Load a .pptx in OBS Scripts';
          document.getElementById('notes').textContent='No notes available';
          document.getElementById('notes').classList.add('empty');
          return;
        }

        document.getElementById('badge').style.display='block';
        document.getElementById('slideNo').textContent=s.current_index+1;
        document.getElementById('slideTotal').textContent=s.total_slides;
        document.getElementById('count').textContent=(s.current_index+1)+' / '+s.total_slides;
        document.getElementById('fill').style.width=((s.current_index+1)/s.total_slides*100)+'%';

        if(s.current_index!==currentIndex){
          currentIndex=s.current_index;
          const img=document.getElementById('currentSlide');
          img.src=withQ('/api/slide/'+s.current_index+'?t='+Date.now());
          img.style.display='block';
          document.getElementById('placeholder').style.display='none';
        }

        const nextPreview=document.getElementById('nextPreview');
        if(s.has_next){
          nextPreview.innerHTML='<img src="'+withQ('/api/slide/'+(s.current_index+1)+'?t='+Date.now())+'" alt="Next">';
        }else{
          nextPreview.innerHTML='<div class="empty">Last slide</div>';
        }

        const notes=document.getElementById('notes');
        if(s.current_notes&&s.current_notes.trim()){
          notes.textContent=s.current_notes;
          notes.classList.remove('empty');
        }else{
          notes.textContent='No presenter notes on this slide';
          notes.classList.add('empty');
        }
      }catch(_err){}
    }
    document.addEventListener('keydown',(event)=>{
      if(event.key==='ArrowRight'||event.key==='PageDown'||event.key===' '){cmd('next');event.preventDefault();}
      if(event.key==='ArrowLeft'||event.key==='PageUp'||event.key==='Backspace'){cmd('prev');event.preventDefault();}
      if(event.key==='b'||event.key==='B'){cmd('black');}
      if(event.key==='Home'){cmd('first');}
      if(event.key==='End'){cmd('last');}
    });
    setInterval(poll,250);
    poll();
  </script>
</body>
</html>
"""


_HTML_BOOTH = """<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>PPTBridge Booth</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    :root{
      --bg:#0c0f15;
      --panel:#141a23;
      --border:#293240;
      --accent:#e7ff5f;
      --accent-2:#5fd7ff;
      --text:#eef4fb;
      --muted:#90a0b6;
      --danger:#ff5f6d;
    }
    html,body{width:100%;height:100%;background:linear-gradient(180deg,#0a0e13,#111720);color:var(--text);font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;overflow:hidden}
    .app{display:grid;grid-template-rows:62px auto 1fr auto 100px;height:100vh}
    .top{display:flex;align-items:center;gap:14px;padding:0 22px;border-bottom:1px solid var(--border);background:rgba(10,14,19,.9)}
    .title{font-size:18px;font-weight:800}
    .title span{color:var(--accent)}
    .tag{padding:6px 12px;border-radius:999px;background:rgba(95,215,255,.12);color:var(--accent-2);font-size:12px;font-weight:700;letter-spacing:.08em}
    .file{margin-left:auto;color:var(--muted);font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .alert{display:none;padding:12px 22px;background:var(--danger);font-size:14px;font-weight:800;letter-spacing:.08em}
    .alert.on{display:block}
    .views{display:grid;grid-template-columns:1fr 1fr;gap:16px;padding:16px 22px;min-height:0}
    .panel{display:flex;flex-direction:column;gap:8px;min-height:0}
    .label{font-size:12px;font-weight:700;letter-spacing:.12em;text-transform:uppercase}
    .label.current{color:var(--accent)}
    .label.next{color:var(--accent-2)}
    .frame{flex:1;background:#000;border:2px solid var(--border);border-radius:20px;display:flex;align-items:center;justify-content:center;overflow:hidden}
    .frame img{max-width:100%;max-height:100%;object-fit:contain}
    .empty{color:#445265;font-size:14px}
    .notes{padding:0 22px 16px}
    .notesbox{background:var(--panel);border:1px solid var(--border);border-radius:18px;padding:16px;font-size:17px;line-height:1.55;white-space:pre-wrap;min-height:110px}
    .notesbox.empty{color:var(--muted);font-style:italic}
    .controls{display:grid;grid-template-columns:1fr 130px 1fr 180px;border-top:1px solid var(--border);background:rgba(10,14,19,.9)}
    button{border:none;background:none;color:inherit;cursor:pointer;font:inherit}
    .btn{display:flex;align-items:center;justify-content:center;height:100px;font-size:28px;font-weight:800}
    .btn.prev{border-right:1px solid var(--border)}
    .btn.next{background:var(--accent);color:#0b0f13}
    .btn.next:disabled,.btn.prev:disabled{opacity:.28;cursor:default}
    .btn.black{border-left:1px solid var(--border);font-size:20px;color:var(--danger)}
    .counter{display:flex;align-items:center;justify-content:center;font-size:28px;font-variant-numeric:tabular-nums;border-right:1px solid var(--border)}
    .hint{position:fixed;bottom:10px;left:50%;transform:translateX(-50%);font-size:12px;color:var(--muted)}
  </style>
</head>
<body>
  <div class="app">
    <div class="top">
      <div class="title">PPT<span>Bridge</span></div>
      <div class="tag">REŽIJA</div>
      <div class="file" id="file">No presentation loaded</div>
    </div>
    <div class="alert" id="alert">BLACK SCREEN IS LIVE</div>
    <div class="views">
      <div class="panel">
        <div class="label current">Current slide</div>
        <div class="frame" id="currentFrame"><div class="empty">Load a .pptx in OBS Scripts</div></div>
      </div>
      <div class="panel">
        <div class="label next">Next slide</div>
        <div class="frame" id="nextFrame"><div class="empty">No next slide</div></div>
      </div>
    </div>
    <div class="notes">
      <div class="notesbox empty" id="notes">No presenter notes yet</div>
    </div>
    <div class="controls">
      <button class="btn prev" id="prevBtn" onclick="cmd('prev')" disabled>Prev</button>
      <div class="counter" id="counter">0 / 0</div>
      <button class="btn next" id="nextBtn" onclick="cmd('next')" disabled>Next</button>
      <button class="btn black" onclick="cmd('black')">Black</button>
    </div>
  </div>
  <div class="hint">Right / Page Down / Space = next · Left / Page Up / Backspace = previous · B = black</div>
  <script>
    function withQ(path){
      const q=window.location.search;
      return q?path+(path.includes('?')?'&':'?')+q.slice(1):path;
    }
    async function cmd(name){
      try{await fetch(withQ('/api/cmd/'+name),{method:'POST'});}catch(_err){}
    }
    async function poll(){
      try{
        const res=await fetch(withQ('/api/state'));
        if(!res.ok)return;
        const s=await res.json();
        document.getElementById('file').textContent=s.pptx_name||'No presentation loaded';
        document.getElementById('alert').classList.toggle('on',!!s.black_screen);

        if(s.loading){return;}
        if(!s.loaded){
          document.getElementById('counter').textContent='0 / 0';
          return;
        }

        document.getElementById('currentFrame').innerHTML='<img src="'+withQ('/api/slide/'+s.current_index+'?t='+Date.now())+'" alt="Current">';
        if(s.has_next){
          document.getElementById('nextFrame').innerHTML='<img src="'+withQ('/api/slide/'+(s.current_index+1)+'?t='+Date.now())+'" alt="Next">';
        }else{
          document.getElementById('nextFrame').innerHTML='<div class="empty">Last slide</div>';
        }

        document.getElementById('counter').textContent=(s.current_index+1)+' / '+s.total_slides;
        document.getElementById('prevBtn').disabled=!s.has_prev;
        document.getElementById('nextBtn').disabled=!s.has_next;

        const notes=document.getElementById('notes');
        if(s.current_notes&&s.current_notes.trim()){
          notes.textContent=s.current_notes;
          notes.classList.remove('empty');
        }else{
          notes.textContent='No presenter notes on this slide';
          notes.classList.add('empty');
        }
      }catch(_err){}
    }
    document.addEventListener('keydown',(event)=>{
      if(event.key==='ArrowRight'||event.key==='PageDown'||event.key===' '){cmd('next');event.preventDefault();}
      if(event.key==='ArrowLeft'||event.key==='PageUp'||event.key==='Backspace'){cmd('prev');event.preventDefault();}
      if(event.key==='b'||event.key==='B'){cmd('black');}
      if(event.key==='Home'){cmd('first');}
      if(event.key==='End'){cmd('last');}
    });
    setInterval(poll,250);
    poll();
  </script>
</body>
</html>
"""


def _url_card(title, url, tone):
    return (
        f'<div class="url-card">'
        f'<div class="url-title {tone}">{title}</div>'
        f'<div class="url-value">{url}</div>'
        f'<button class="copy" onclick="copyUrl({json.dumps(url)},this)">copy</button>'
        f"</div>"
    )


def _render_control_page(snapshot):
    local_cards = [
        _url_card("Slide (local)", snapshot["slide_url_local"], "accent"),
        _url_card("Presenter (local)", snapshot["presenter_url_local"], "blue"),
        _url_card("Booth (local)", snapshot["booth_url_local"], "red"),
        _url_card("Control (local)", snapshot["control_url_local"], "muted"),
    ]

    lan_cards = []
    if snapshot.get("slide_url_lan"):
        lan_cards = [
            _url_card("Slide (LAN)", snapshot["slide_url_lan"], "accent"),
            _url_card("Presenter (LAN)", snapshot["presenter_url_lan"], "blue"),
            _url_card("Booth (LAN)", snapshot["booth_url_lan"], "red"),
            _url_card("Control (LAN)", snapshot["control_url_lan"], "muted"),
        ]

    html = """<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>PPTBridge Control</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    :root{
      --bg:#f5f2ea;
      --ink:#181514;
      --panel:rgba(255,255,255,.76);
      --border:rgba(24,21,20,.12);
      --accent:#d9ff4d;
      --blue:#7fd9ff;
      --red:#ff8795;
      --muted:#726a64;
      --shadow:0 16px 50px rgba(20,17,14,.12);
    }
    body{
      min-height:100vh;
      font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
      color:var(--ink);
      background:
        radial-gradient(circle at top left, rgba(217,255,77,.5), transparent 26%),
        radial-gradient(circle at bottom right, rgba(127,217,255,.45), transparent 24%),
        linear-gradient(180deg,#f7f3eb,#eee7db);
      padding:32px;
    }
    .wrap{max-width:1200px;margin:0 auto}
    .hero{display:flex;align-items:flex-end;justify-content:space-between;gap:20px;margin-bottom:22px}
    h1{font-size:42px;line-height:.98;font-weight:900;letter-spacing:-.04em}
    h1 span{color:#3c4630}
    .sub{max-width:520px;color:var(--muted);font-size:15px;line-height:1.55}
    .badge{display:inline-flex;align-items:center;gap:10px;padding:10px 14px;border:1px solid var(--border);border-radius:999px;background:rgba(255,255,255,.65);box-shadow:var(--shadow);font-size:13px}
    .badge strong{font-weight:800}
    .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px;margin-bottom:18px}
    .url-card,.panel{background:var(--panel);backdrop-filter:blur(14px);border:1px solid var(--border);border-radius:24px;box-shadow:var(--shadow)}
    .url-card{padding:18px;display:flex;flex-direction:column;gap:10px}
    .url-title{font-size:12px;font-weight:800;letter-spacing:.12em;text-transform:uppercase}
    .url-title.accent{color:#687c12}
    .url-title.blue{color:#2c6c8e}
    .url-title.red{color:#b63e52}
    .url-title.muted{color:var(--muted)}
    .url-value{font-size:13px;line-height:1.5;word-break:break-word}
    .copy{align-self:flex-start;border:none;border-radius:999px;padding:8px 12px;background:#181514;color:#fff;font-size:12px;cursor:pointer}
    .main{display:grid;grid-template-columns:minmax(0,1fr) 320px;gap:18px}
    .panel{padding:18px}
    .controls{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:14px}
    .controls button{border:none;border-radius:999px;padding:12px 18px;font-size:14px;font-weight:700;cursor:pointer}
    .controls .primary{background:#181514;color:#fff}
    .controls .danger{background:#fff;color:#b63e52;border:1px solid rgba(182,62,82,.24)}
    .counter{padding:12px 16px;border-radius:999px;border:1px solid var(--border);font-variant-numeric:tabular-nums;background:rgba(255,255,255,.74)}
    .preview-row{display:grid;grid-template-columns:minmax(0,1fr) 220px;gap:14px;margin-bottom:14px}
    .preview{background:#111;border-radius:18px;overflow:hidden;display:flex;align-items:center;justify-content:center;min-height:160px}
    .preview img{width:100%;height:100%;object-fit:contain}
    .empty{color:#4f5a68;font-size:14px}
    .label{font-size:12px;font-weight:800;letter-spacing:.12em;text-transform:uppercase;margin-bottom:8px}
    .notes{font-size:15px;line-height:1.6;white-space:pre-wrap;min-height:100px}
    .notes.empty{color:var(--muted);font-style:italic}
    .thumb-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:10px;margin-top:14px}
    .thumb{border:2px solid transparent;border-radius:16px;overflow:hidden;background:#111;cursor:pointer;position:relative}
    .thumb.active{border-color:#181514}
    .thumb img{width:100%;aspect-ratio:16/9;object-fit:contain;display:block}
    .thumb span{position:absolute;right:8px;bottom:8px;padding:4px 6px;border-radius:999px;background:rgba(0,0,0,.75);color:#fff;font-size:11px}
    .side-list{display:flex;flex-direction:column;gap:12px}
    .meta{font-size:13px;color:var(--muted);line-height:1.6}
    .meta strong{color:var(--ink)}
    @media (max-width: 900px){
      body{padding:18px}
      .hero{flex-direction:column;align-items:flex-start}
      .main{grid-template-columns:1fr}
      .preview-row{grid-template-columns:1fr}
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div>
        <h1>PPTBridge<br><span>for OBS</span></h1>
        <div class="sub">PowerPoint slides, presenter notes, stage view, and booth control in one practical OBS workflow. Built by <strong>Srđan Kotarlić</strong>.</div>
      </div>
      <div class="badge"><strong>v__VERSION__</strong><span>Browser Source workflow</span></div>
    </div>

    <div class="grid">
      __LOCAL_URLS__
    </div>

    __LAN_SECTION__

    <div class="main">
      <div class="panel">
        <div class="controls">
          <button onclick="cmd('prev')" id="prevBtn">Prev</button>
          <div class="counter" id="counter">0 / 0</div>
          <button class="primary" onclick="cmd('next')" id="nextBtn">Next</button>
          <button class="danger" onclick="cmd('black')">Black</button>
        </div>

        <div class="preview-row">
          <div>
            <div class="label">Current slide</div>
            <div class="preview" id="currentPreview"><div class="empty">No presentation loaded</div></div>
          </div>
          <div>
            <div class="label">Next slide</div>
            <div class="preview" id="nextPreview"><div class="empty">No next slide</div></div>
          </div>
        </div>

        <div class="label">Notes</div>
        <div class="notes empty" id="notes">Load a .pptx in OBS Scripts.</div>

        <div class="label" style="margin-top:18px">All slides</div>
        <div class="thumb-grid" id="thumbGrid"></div>
      </div>

      <div class="side-list">
        <div class="panel">
          <div class="label">Project status</div>
          <div class="meta">
            <strong>This version is a script MVP</strong><br>
            It gives you Slide and Presenter views now, while keeping the door open for a future native OBS source plugin.
          </div>
        </div>
        <div class="panel">
          <div class="label">Stage control</div>
          <div class="meta">
            Spotlight and similar remotes usually work well when they send keyboard keys like <strong>Page Down</strong>, <strong>Page Up</strong>, arrows, or <strong>Space</strong>.
          </div>
        </div>
        <div class="panel">
          <div class="label">Security</div>
          <div class="meta" id="securityMeta">Remote token: disabled</div>
        </div>
      </div>
    </div>
  </div>
  <script>
    const TOKEN_ENABLED=__TOKEN_ENABLED__;
    function withQ(path){
      const q=window.location.search;
      return q?path+(path.includes('?')?'&':'?')+q.slice(1):path;
    }
    function copyUrl(url,button){
      navigator.clipboard.writeText(url);
      const old=button.textContent;
      button.textContent='copied';
      setTimeout(()=>{button.textContent=old;},1000);
    }
    async function cmd(name){
      try{await fetch(withQ('/api/cmd/'+name),{method:'POST'});}catch(_err){}
    }
    let builtSlides=0;
    async function poll(){
      try{
        const res=await fetch(withQ('/api/state'));
        if(!res.ok)return;
        const s=await res.json();
        document.getElementById('securityMeta').textContent='Remote token: '+(s.remote_token_enabled?'enabled':'disabled');

        if(s.loading){return;}
        if(!s.loaded){
          document.getElementById('counter').textContent='0 / 0';
          return;
        }

        document.getElementById('counter').textContent=(s.current_index+1)+' / '+s.total_slides;
        document.getElementById('prevBtn').disabled=!s.has_prev;
        document.getElementById('nextBtn').disabled=!s.has_next;
        document.getElementById('currentPreview').innerHTML='<img src="'+withQ('/api/slide/'+s.current_index+'?t='+Date.now())+'" alt="Current">';
        if(s.has_next){
          document.getElementById('nextPreview').innerHTML='<img src="'+withQ('/api/slide/'+(s.current_index+1)+'?t='+Date.now())+'" alt="Next">';
        }else{
          document.getElementById('nextPreview').innerHTML='<div class="empty">Last slide</div>';
        }

        const notes=document.getElementById('notes');
        if(s.current_notes&&s.current_notes.trim()){
          notes.textContent=s.current_notes;
          notes.classList.remove('empty');
        }else{
          notes.textContent='No presenter notes on this slide';
          notes.classList.add('empty');
        }

        const grid=document.getElementById('thumbGrid');
        if(builtSlides!==s.total_slides){
          grid.innerHTML='';
          for(let i=0;i<s.total_slides;i++){
            const item=document.createElement('button');
            item.className='thumb';
            item.onclick=()=>cmd('goto/'+i);
            item.innerHTML='<img src="'+withQ('/api/slide/'+i+'?t='+Date.now())+'" alt="Slide '+(i+1)+'"><span>'+(i+1)+'</span>';
            grid.appendChild(item);
          }
          builtSlides=s.total_slides;
        }
        Array.from(grid.children).forEach((el,index)=>el.classList.toggle('active',index===s.current_index));
      }catch(_err){}
    }
    document.addEventListener('keydown',(event)=>{
      if(event.key==='ArrowRight'||event.key==='PageDown'||event.key===' '){cmd('next');event.preventDefault();}
      if(event.key==='ArrowLeft'||event.key==='PageUp'||event.key==='Backspace'){cmd('prev');event.preventDefault();}
      if(event.key==='b'||event.key==='B'){cmd('black');}
      if(event.key==='Home'){cmd('first');}
      if(event.key==='End'){cmd('last');}
    });
    setInterval(poll,300);
    poll();
  </script>
</body>
</html>
"""

    lan_section = ""
    if lan_cards:
        lan_section = (
            '<div class="grid" style="margin-bottom:18px">'
            + "".join(lan_cards)
            + "</div>"
        )

    return (
        html.replace("__VERSION__", VERSION)
        .replace("__LOCAL_URLS__", "".join(local_cards))
        .replace("__LAN_SECTION__", lan_section)
        .replace("__TOKEN_ENABLED__", "true" if snapshot.get("remote_token_enabled") else "false")
    )


class _PPTBridgeHandler(BaseHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return

    def _send(self, content, content_type="text/html; charset=utf-8", code=200):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if isinstance(content, str):
            content = content.encode("utf-8")
        self.wfile.write(content)

    def _authorized(self, parsed):
        if not _remote_token:
            return True
        token = parse_qs(parsed.query).get("token", [""])[0]
        return token == _remote_token

    def _deny_if_unauthorized(self, parsed):
        if self._authorized(parsed):
            return False
        self._send("Forbidden", "text/plain; charset=utf-8", 403)
        return True

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/favicon.ico":
            self._send("", "text/plain; charset=utf-8", 204)
            return

        if self._deny_if_unauthorized(parsed):
            return

        snapshot = _state_snapshot()

        if path == "/" or path == "/control":
            self._send(_render_control_page(snapshot))
            return
        if path == "/slide":
            self._send(_HTML_SLIDE)
            return
        if path == "/presenter":
            self._send(_HTML_PRESENTER)
            return
        if path == "/booth":
            self._send(_HTML_BOOTH)
            return
        if path == "/api/state":
            self._send(json.dumps(snapshot), "application/json; charset=utf-8")
            return
        if path.startswith("/api/slide/"):
            try:
                index = int(path.split("/")[-1])
                image_path = _current_slide_path(index)
                if image_path and os.path.exists(image_path):
                    with open(image_path, "rb") as handle:
                        self._send(handle.read(), "image/png")
                else:
                    self._send("", "text/plain; charset=utf-8", 404)
            except Exception:
                self._send("", "text/plain; charset=utf-8", 404)
            return

        self._send("Not found", "text/plain; charset=utf-8", 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if self._deny_if_unauthorized(parsed):
            return

        if path == "/api/cmd/next":
            _next_slide()
        elif path == "/api/cmd/prev":
            _prev_slide()
        elif path == "/api/cmd/black":
            _toggle_black()
        elif path == "/api/cmd/first":
            _goto_slide(0)
        elif path == "/api/cmd/last":
            total = _state_snapshot().get("total_slides", 0)
            if total > 0:
                _goto_slide(total - 1)
        elif path.startswith("/api/cmd/goto/"):
            try:
                index = int(path.split("/")[-1])
                _goto_slide(index)
            except Exception:
                pass

        self._send(json.dumps({"ok": True}), "application/json; charset=utf-8")


def _start_server():
    global _server, _server_thread

    _stop_server()

    bind_host = "0.0.0.0" if _allow_lan_control else "127.0.0.1"
    try:
        _server = ThreadingHTTPServer((bind_host, _port), _PPTBridgeHandler)
        _server_thread = threading.Thread(
            target=_server.serve_forever,
            daemon=True,
            name="PPTBridgeHTTP",
        )
        _server_thread.start()
        _refresh_network_state()

        snapshot = _state_snapshot()
        obs.script_log(obs.LOG_INFO, f"PPTBridge: HTTP server started on {bind_host}:{_port}")
        obs.script_log(obs.LOG_INFO, f"PPTBridge: Slide URL     -> {snapshot['slide_url_local']}")
        obs.script_log(obs.LOG_INFO, f"PPTBridge: Presenter URL -> {snapshot['presenter_url_local']}")
        obs.script_log(obs.LOG_INFO, f"PPTBridge: Booth URL     -> {snapshot['booth_url_local']}")
        if snapshot.get("control_url_lan"):
            obs.script_log(obs.LOG_INFO, f"PPTBridge: LAN Control   -> {snapshot['control_url_lan']}")
    except Exception as exc:
        obs.script_log(obs.LOG_ERROR, f"PPTBridge: failed to start server: {exc}")


def _stop_server():
    global _server
    if _server:
        try:
            _server.shutdown()
        except Exception:
            pass
        _server = None


def script_description():
    _refresh_network_state()
    snapshot = _state_snapshot()

    dep_lines = []
    if _lo_path:
        dep_lines.append("✓ LibreOffice found")
    else:
        dep_lines.append("✗ LibreOffice missing")

    try:
        import Quartz  # noqa: F401

        dep_lines.append("✓ macOS Quartz PDF renderer available")
    except ImportError:
        if _pdftoppm_path:
            dep_lines.append("✓ pdftoppm fallback found")
        else:
            dep_lines.append("✗ No PDF fallback renderer found")

    dep_html = "".join(f"<p><code>{line}</code></p>" for line in dep_lines)

    lan_html = ""
    if snapshot.get("control_url_lan"):
        lan_html = (
            f"<p><b>LAN control:</b> <code>{snapshot['control_url_lan']}</code></p>"
            f"<p><b>LAN booth:</b> <code>{snapshot['booth_url_lan']}</code></p>"
        )

    return (
        "<h2>PPTBridge for OBS</h2>"
        f"<p><b>by {AUTHOR}</b> — v{VERSION}</p>"
        "<p>PowerPoint in OBS with Slide view, Presenter view, notes, and booth control.</p>"
        "<p><b>This release is an OBS script + Browser Source workflow.</b></p>"
        "<hr>"
        "<p><b>Dependencies</b></p>"
        f"{dep_html}"
        "<hr>"
        "<p><b>Local Browser Source URLs</b></p>"
        f"<p>Slide: <code>{snapshot['slide_url_local']}</code></p>"
        f"<p>Presenter: <code>{snapshot['presenter_url_local']}</code></p>"
        f"<p>Booth: <code>{snapshot['booth_url_local']}</code></p>"
        f"<p>Control: <code>{snapshot['control_url_local']}</code></p>"
        f"{lan_html}"
        "<hr>"
        "<p><b>Hotkeys</b>: OBS -> Settings -> Hotkeys -> search for <code>PPTBridge</code></p>"
    )


def script_properties():
    props = obs.obs_properties_create()

    obs.obs_properties_add_path(
        props,
        "pptx_path",
        "PowerPoint File (.pptx)",
        obs.OBS_PATH_FILE,
        "PowerPoint (*.pptx)",
        None,
    )
    obs.obs_properties_add_int(props, "port", "Server Port", 1024, 65535, 1)
    obs.obs_properties_add_int(props, "dpi", "Slide Quality (DPI)", 72, 600, 1)
    obs.obs_properties_add_bool(props, "allow_lan", "Allow LAN Control")
    obs.obs_properties_add_text(
        props,
        "remote_token",
        "Remote Token (optional)",
        obs.OBS_TEXT_DEFAULT,
    )

    obs.obs_properties_add_button(props, "btn_load", "Load Presentation", _on_load_clicked)
    obs.obs_properties_add_button(props, "btn_prev", "Previous Slide", _on_prev_clicked)
    obs.obs_properties_add_button(props, "btn_next", "Next Slide", _on_next_clicked)
    obs.obs_properties_add_button(props, "btn_black", "Toggle Black Screen", _on_black_clicked)
    obs.obs_properties_add_button(props, "btn_open", "Open Control Panel", _on_open_clicked)
    return props


def script_defaults(settings):
    obs.obs_data_set_default_int(settings, "port", 8765)
    obs.obs_data_set_default_int(settings, "dpi", 200)
    obs.obs_data_set_default_bool(settings, "allow_lan", True)
    obs.obs_data_set_default_string(settings, "remote_token", "")


def script_update(settings):
    global _pptx_path, _port, _dpi, _allow_lan_control, _remote_token

    _pptx_path = obs.obs_data_get_string(settings, "pptx_path")
    new_port = obs.obs_data_get_int(settings, "port")
    new_dpi = obs.obs_data_get_int(settings, "dpi")
    new_allow_lan = obs.obs_data_get_bool(settings, "allow_lan")
    new_remote_token = obs.obs_data_get_string(settings, "remote_token").strip()

    restart_needed = (
        new_port != _port
        or new_allow_lan != _allow_lan_control
        or new_remote_token != _remote_token
    )

    _port = new_port
    _dpi = new_dpi
    _allow_lan_control = new_allow_lan
    _remote_token = new_remote_token
    _refresh_network_state()

    if restart_needed:
        _start_server()
    else:
        _update_state()


def script_load(settings):
    global _hk_next, _hk_prev, _hk_black

    _refresh_network_state()
    _start_server()

    _hk_next = obs.obs_hotkey_register_frontend(
        "pptbridge_next",
        "PPTBridge: Next Slide",
        _hotkey_next,
    )
    _hk_prev = obs.obs_hotkey_register_frontend(
        "pptbridge_prev",
        "PPTBridge: Previous Slide",
        _hotkey_prev,
    )
    _hk_black = obs.obs_hotkey_register_frontend(
        "pptbridge_black",
        "PPTBridge: Toggle Black Screen",
        _hotkey_black,
    )

    hk_next_data = obs.obs_data_get_array(settings, "pptbridge_next")
    obs.obs_hotkey_load(_hk_next, hk_next_data)
    obs.obs_data_array_release(hk_next_data)

    hk_prev_data = obs.obs_data_get_array(settings, "pptbridge_prev")
    obs.obs_hotkey_load(_hk_prev, hk_prev_data)
    obs.obs_data_array_release(hk_prev_data)

    hk_black_data = obs.obs_data_get_array(settings, "pptbridge_black")
    obs.obs_hotkey_load(_hk_black, hk_black_data)
    obs.obs_data_array_release(hk_black_data)


def script_save(settings):
    hk_next_data = obs.obs_hotkey_save(_hk_next)
    obs.obs_data_set_array(settings, "pptbridge_next", hk_next_data)
    obs.obs_data_array_release(hk_next_data)

    hk_prev_data = obs.obs_hotkey_save(_hk_prev)
    obs.obs_data_set_array(settings, "pptbridge_prev", hk_prev_data)
    obs.obs_data_array_release(hk_prev_data)

    hk_black_data = obs.obs_hotkey_save(_hk_black)
    obs.obs_data_set_array(settings, "pptbridge_black", hk_black_data)
    obs.obs_data_array_release(hk_black_data)


def script_unload():
    global _slides_dir

    _stop_server()
    if _slides_dir and os.path.exists(_slides_dir):
        shutil.rmtree(_slides_dir, ignore_errors=True)
        _slides_dir = None


def _on_load_clicked(_props, _prop):
    if not _pptx_path:
        _set_loading(False, "Choose a PowerPoint file first.")
        obs.script_log(obs.LOG_WARNING, "PPTBridge: no .pptx selected")
        return True

    thread = threading.Thread(target=_load_pptx, args=(_pptx_path,), daemon=True)
    thread.start()
    return True


def _on_prev_clicked(_props, _prop):
    _prev_slide()
    return True


def _on_next_clicked(_props, _prop):
    _next_slide()
    return True


def _on_black_clicked(_props, _prop):
    _toggle_black()
    return True


def _on_open_clicked(_props, _prop):
    import webbrowser

    control_url = _state_snapshot().get("control_url_local") or f"http://127.0.0.1:{_port}/"
    webbrowser.open(control_url)
    return True


def _hotkey_next(pressed):
    if pressed:
        _next_slide()


def _hotkey_prev(pressed):
    if pressed:
        _prev_slide()


def _hotkey_black(pressed):
    if pressed:
        _toggle_black()
