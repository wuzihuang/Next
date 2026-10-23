#!/usr/bin/env python3
"""fonts.js — one extra face look.py's three roles cannot hold: Doto Regular (400) for the launch mark's second line.
Subset to printable ASCII, inlined as base64 woff2, loaded as 'LookDotoRegular' before __ready."""
import base64, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "onetake-src" / "scripts"))
from look import subset_face
chars = [chr(c) for c in range(0x20, 0x7F)]
data, _ = subset_face(pathlib.Path(__file__).resolve().parents[1] / "fonts" / "Doto-Regular.ttf", None, chars)
b64 = base64.b64encode(data).decode()
js = """(function(){
  const bytes = b64 => Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const f = new FontFace('LookDotoRegular', bytes('%s'), { weight: '400' });
  document.fonts.add(f); window.FONTS_READY = f.load();
})();
""" % b64
pathlib.Path(__file__).with_name("fonts.js").write_text(js)
print("fonts.js", len(js) // 1024, "KB")
