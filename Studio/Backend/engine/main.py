from __future__ import annotations

import os

from .api import run


if __name__ == "__main__":
    host = os.environ.get("LEXO_HOST", "127.0.0.1").strip() or "127.0.0.1"
    port_raw = os.environ.get("LEXO_PORT", "8765").strip() or "8765"
    run(host=host, port=int(port_raw))
