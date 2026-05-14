from __future__ import annotations

import argparse
import json
import signal
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import frida


DEFAULT_PACKAGE = "su.x2books.app"
DEFAULT_PROCESS_NAMES = ("su.x2books.app", "2Books")
DEFAULT_TARGET = "/app_flutter/books/"
DEFAULT_PAGE_MARKER = "/pages/"

HOOK_SOURCE = r"""
'use strict';

const tracked = new Map();
const O_ACCMODE = 0x3;
const O_WRONLY = 0x1;
const O_RDWR = 0x2;

function resolveExport(name) {
  if (typeof Module !== 'undefined') {
    if (typeof Module.findGlobalExportByName === 'function') {
      try {
        const addr = Module.findGlobalExportByName(name);
        if (addr !== null) {
          return addr;
        }
      } catch (e) {}
    }
    if (typeof Module.getGlobalExportByName === 'function') {
      try {
        return Module.getGlobalExportByName(name);
      } catch (e) {}
    }
  }
  if (typeof DebugSymbol !== 'undefined' && typeof DebugSymbol.fromName === 'function') {
    try {
      const matches = DebugSymbol.fromName(name);
      if (matches !== null && matches.address !== undefined && !matches.address.isNull()) {
        return matches.address;
      }
    } catch (e) {}
  }
  return null;
}

function readCString(ptrValue) {
  if (ptrValue.isNull()) {
    return null;
  }
  try {
    return ptr(ptrValue).readUtf8String();
  } catch (e) {
    return null;
  }
}

function shouldTrack(path) {
  return path !== null &&
         path.indexOf(TARGET_SUBSTRING) !== -1 &&
         path.indexOf(PAGE_MARKER) !== -1 &&
         (path.endsWith('.json.gz') || path.endsWith('.json.gz.tmp'));
}

function flagsSuggestWrite(flags) {
  if (flags === null || flags === undefined) {
    return false;
  }
  const access = flags & O_ACCMODE;
  return access === O_WRONLY || access === O_RDWR;
}

function captureBacktrace(context) {
  try {
    return Thread.backtrace(context, Backtracer.ACCURATE)
      .map(function (addr) { return DebugSymbol.fromAddress(addr).toString(); });
  } catch (e) {
    return ['<backtrace failed: ' + String(e) + '>'];
  }
}

function noteOpen(fd, path, viaName) {
  if (fd < 0 || !shouldTrack(path)) {
    return;
  }
  tracked.set(fd, path);
  send({ type: 'open', fd: fd, path: path, via: viaName });
}

function hookOpenLike(exportName, pathArgIndex, flagsArgIndex) {
  const addr = resolveExport(exportName);
  if (addr === null) {
    return;
  }
  Interceptor.attach(addr, {
    onEnter(args) {
      this.path = readCString(args[pathArgIndex]);
      this.flags = flagsArgIndex === null ? null : args[flagsArgIndex].toInt32();
      this.bt = (this.path !== null && this.path.endsWith('.tmp') && flagsSuggestWrite(this.flags))
        ? captureBacktrace(this.context)
        : null;
    },
    onLeave(retval) {
      noteOpen(retval.toInt32(), this.path, exportName);
      if (retval.toInt32() >= 0 && shouldTrack(this.path)) {
        send({
          type: 'open_flags',
          fd: retval.toInt32(),
          path: this.path,
          via: exportName,
          flags: this.flags,
          backtrace: this.bt
        });
      }
    }
  });
}

hookOpenLike('open', 0, 1);
hookOpenLike('open64', 0, 1);
hookOpenLike('openat', 1, 2);
hookOpenLike('openat64', 1, 2);

const writeAddr = resolveExport('write');
if (writeAddr !== null) {
  Interceptor.attach(writeAddr, {
    onEnter(args) {
      this.fd = args[0].toInt32();
      this.buf = args[1];
      this.count = args[2].toInt32();
      this.path = tracked.get(this.fd) || null;
      this.shouldSend = this.path !== null && this.count > 0;
    },
    onLeave(retval) {
      if (!this.shouldSend) {
        return;
      }
      const actual = retval.toInt32();
      if (actual <= 0) {
        send({
          type: 'write_result',
          fd: this.fd,
          path: this.path,
          requested: this.count,
          actual: actual
        });
        return;
      }
      let chunk = null;
      try {
        chunk = this.buf.readByteArray(actual);
      } catch (e) {
        send({
          type: 'read_error',
          fd: this.fd,
          path: this.path,
          requested: this.count,
          actual: actual,
          error: String(e)
        });
        return;
      }
      send({
        type: 'write',
        fd: this.fd,
        path: this.path,
        requested: this.count,
        actual: actual
      }, chunk);
    }
  });
}

function hookPwriteLike(exportName) {
  const addr = resolveExport(exportName);
  if (addr === null) {
    return;
  }
  Interceptor.attach(addr, {
    onEnter(args) {
      this.fd = args[0].toInt32();
      this.buf = args[1];
      this.count = args[2].toInt32();
      this.path = tracked.get(this.fd) || null;
      this.shouldSend = this.path !== null && this.count > 0;
    },
    onLeave(retval) {
      if (!this.shouldSend) {
        return;
      }
      const actual = retval.toInt32();
      if (actual <= 0) {
        send({
          type: 'pwrite_result',
          via: exportName,
          fd: this.fd,
          path: this.path,
          requested: this.count,
          actual: actual
        });
        return;
      }
      let chunk = null;
      try {
        chunk = this.buf.readByteArray(actual);
      } catch (e) {
        send({
          type: 'read_error',
          via: exportName,
          fd: this.fd,
          path: this.path,
          requested: this.count,
          actual: actual,
          error: String(e)
        });
        return;
      }
      send({
        type: 'write',
        via: exportName,
        fd: this.fd,
        path: this.path,
        requested: this.count,
        actual: actual
      }, chunk);
    }
  });
}

hookPwriteLike('pwrite');
hookPwriteLike('pwrite64');

function hookWritevLike(exportName) {
  const addr = resolveExport(exportName);
  if (addr === null) {
    return;
  }
  Interceptor.attach(addr, {
    onEnter(args) {
      this.fd = args[0].toInt32();
      this.iov = args[1];
      this.iovcnt = args[2].toInt32();
      this.path = tracked.get(this.fd) || null;
    },
    onLeave(retval) {
      if (this.path === null) {
        return;
      }
      send({
        type: 'writev',
        via: exportName,
        fd: this.fd,
        path: this.path,
        iovcnt: this.iovcnt,
        actual: retval.toInt32()
      });
    }
  });
}

hookWritevLike('writev');

function hookFdMetadataCall(exportName, fdArgIndex, extraReader) {
  const addr = resolveExport(exportName);
  if (addr === null) {
    return;
  }
  Interceptor.attach(addr, {
    onEnter(args) {
      this.fd = args[fdArgIndex].toInt32();
      this.path = tracked.get(this.fd) || null;
      this.extra = extraReader !== null ? extraReader(args) : {};
    },
    onLeave(retval) {
      if (this.path === null) {
        return;
      }
      const payload = {
        type: exportName,
        fd: this.fd,
        path: this.path,
        result: retval.toInt32()
      };
      for (const key in this.extra) {
        payload[key] = this.extra[key];
      }
      send(payload);
    }
  });
}

hookFdMetadataCall('fsync', 0, null);
hookFdMetadataCall('fdatasync', 0, null);
hookFdMetadataCall('ftruncate', 0, function (args) {
  return { length: args[1].toInt32() };
});
hookFdMetadataCall('ftruncate64', 0, function (args) {
  return { length: args[1].toInt32() };
});
hookFdMetadataCall('lseek', 0, function (args) {
  return { offset: args[1].toInt32(), whence: args[2].toInt32() };
});
hookFdMetadataCall('lseek64', 0, function (args) {
  return { offset: args[1].toInt32(), whence: args[2].toInt32() };
});

const closeAddr = resolveExport('close');
if (closeAddr !== null) {
  Interceptor.attach(closeAddr, {
    onEnter(args) {
      this.fd = args[0].toInt32();
      this.path = tracked.get(this.fd) || null;
    },
    onLeave(retval) {
      if (this.path === null) {
        return;
      }
      tracked.delete(this.fd);
      send({
        type: 'close',
        fd: this.fd,
        path: this.path,
        result: retval.toInt32()
      });
    }
  });
}

function hookRenameLike(exportName, fromIndex, toIndex) {
  const addr = resolveExport(exportName);
  if (addr === null) {
    return;
  }
  Interceptor.attach(addr, {
    onEnter(args) {
      this.fromPath = readCString(args[fromIndex]);
      this.toPath = readCString(args[toIndex]);
    },
    onLeave(retval) {
      if (!shouldTrack(this.fromPath) && !shouldTrack(this.toPath)) {
        return;
      }
      send({
        type: 'rename',
        from_path: this.fromPath,
        to_path: this.toPath,
        via: exportName,
        result: retval.toInt32()
      });
    }
  });
}

hookRenameLike('rename', 0, 1);
hookRenameLike('renameat', 1, 3);

function hookUnlinkLike(exportName, pathArgIndex) {
  const addr = resolveExport(exportName);
  if (addr === null) {
    return;
  }
  Interceptor.attach(addr, {
    onEnter(args) {
      this.path = readCString(args[pathArgIndex]);
    },
    onLeave(retval) {
      if (!shouldTrack(this.path)) {
        return;
      }
      send({
        type: 'unlink',
        path: this.path,
        via: exportName,
        result: retval.toInt32()
      });
    }
  });
}

hookUnlinkLike('unlink', 0);
hookUnlinkLike('unlinkat', 1);

const mmapAddr = resolveExport('mmap');
if (mmapAddr !== null) {
  Interceptor.attach(mmapAddr, {
    onEnter(args) {
      this.fd = args[4].toInt32();
      this.length = args[1].toInt32();
      this.path = tracked.get(this.fd) || null;
    },
    onLeave(retval) {
      if (this.path === null) {
        return;
      }
      send({
        type: 'mmap',
        fd: this.fd,
        path: this.path,
        length: this.length
      });
    }
  });
}

const msyncAddr = resolveExport('msync');
if (msyncAddr !== null) {
  Interceptor.attach(msyncAddr, {
    onEnter(args) {
      this.addr = args[0];
      this.length = args[1].toInt32();
    },
    onLeave(retval) {
      send({
        type: 'msync',
        length: this.length,
        result: retval.toInt32()
      });
    }
  });
}

function syscallName(num) {
  const map = {
    1: 'write',
    18: 'pwrite64',
    20: 'writev',
    74: 'fsync',
    75: 'fdatasync',
    77: 'ftruncate',
    257: 'openat',
    263: 'unlinkat',
    264: 'renameat'
  };
  return map[num] || null;
}

const syscallAddr = resolveExport('syscall');
if (syscallAddr !== null) {
  Interceptor.attach(syscallAddr, {
    onEnter(args) {
      this.num = args[0].toInt32();
      this.name = syscallName(this.num);
      this.fd = null;
      this.path = null;
      this.count = null;
      this.buf = null;

      if (this.name === 'write' || this.name === 'pwrite64' || this.name === 'writev') {
        this.fd = args[1].toInt32();
        this.path = tracked.get(this.fd) || null;
        this.buf = args[2];
        this.count = args[3] !== undefined ? args[3].toInt32() : null;
      } else if (this.name === 'fsync' || this.name === 'fdatasync' || this.name === 'ftruncate') {
        this.fd = args[1].toInt32();
        this.path = tracked.get(this.fd) || null;
      } else if (this.name === 'openat') {
        this.openPath = readCString(args[2]);
        this.openFlags = args[3].toInt32();
      } else if (this.name === 'unlinkat') {
        this.unlinkPath = readCString(args[2]);
      } else if (this.name === 'renameat') {
        this.renameFrom = readCString(args[2]);
        this.renameTo = readCString(args[4]);
      }
    },
    onLeave(retval) {
      if (this.name === null) {
        return;
      }
      if (this.name === 'openat' && shouldTrack(this.openPath)) {
        send({
          type: 'syscall_openat',
          path: this.openPath,
          flags: this.openFlags,
          result: retval.toInt32()
        });
        return;
      }
      if (this.name === 'unlinkat' && shouldTrack(this.unlinkPath)) {
        send({
          type: 'syscall_unlinkat',
          path: this.unlinkPath,
          result: retval.toInt32()
        });
        return;
      }
      if (this.name === 'renameat' && (shouldTrack(this.renameFrom) || shouldTrack(this.renameTo))) {
        send({
          type: 'syscall_renameat',
          from_path: this.renameFrom,
          to_path: this.renameTo,
          result: retval.toInt32()
        });
        return;
      }
      if (this.path !== null) {
        if (this.name === 'write') {
          const actual = retval.toInt32();
          if (actual > 0 && this.buf !== null) {
            try {
              const chunk = this.buf.readByteArray(actual);
              send({
                type: 'write',
                via: 'syscall_write',
                fd: this.fd,
                path: this.path,
                requested: this.count,
                actual: actual
              }, chunk);
              return;
            } catch (e) {
              send({
                type: 'read_error',
                via: 'syscall_write',
                fd: this.fd,
                path: this.path,
                requested: this.count,
                actual: actual,
                error: String(e)
              });
              return;
            }
          }
        }
        send({
          type: 'syscall_' + this.name,
          fd: this.fd,
          path: this.path,
          count: this.count,
          result: retval.toInt32()
        });
      }
    }
  });
}
"""


@dataclass
class OpenFileCapture:
    fd: int
    path: str
    open_ts: float
    via: str | None = None
    chunks: list[bytes] = field(default_factory=list)
    bytes_written: int = 0


def sanitize_filename(name: str) -> str:
    safe = []
    for ch in name:
        if ch.isalnum() or ch in "._-":
            safe.append(ch)
        else:
            safe.append("_")
    return "".join(safe).strip("_") or "unnamed"


def make_hook_source(target_substring: str, page_marker: str) -> str:
    return (
        f"const TARGET_SUBSTRING = {json.dumps(target_substring)};\n"
        f"const PAGE_MARKER = {json.dumps(page_marker)};\n"
        + HOOK_SOURCE
    )


def current_stamp() -> str:
    return time.strftime("%Y%m%d_%H%M%S")


def wait_for_process(
    device: frida.core.Device,
    package: str,
    process_names: list[str],
    poll_seconds: float,
) -> frida.core.Process:
    valid_names = {package, *process_names}
    while True:
        processes = device.enumerate_processes()
        for proc in processes:
            if proc.name in valid_names:
                return proc
        print(
            f"[wait] process not found yet; expected one of {sorted(valid_names)}; retry in {poll_seconds:.1f}s",
            flush=True,
        )
        time.sleep(poll_seconds)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Hook 2Books page writes via Frida and save real write() outputs."
    )
    parser.add_argument("--package", default=DEFAULT_PACKAGE)
    parser.add_argument(
        "--process-name",
        action="append",
        default=list(DEFAULT_PROCESS_NAMES),
        help="Explicit process name accepted by Frida. Can be repeated.",
    )
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--target-substring", default=DEFAULT_TARGET)
    parser.add_argument("--page-marker", default=DEFAULT_PAGE_MARKER)
    parser.add_argument("--poll-seconds", type=float, default=1.0)
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    payload_dir = out_dir / "payloads"
    payload_dir.mkdir(parents=True, exist_ok=True)
    meta_path = out_dir / "events.jsonl"
    summary_path = out_dir / "session.json"

    stop = False
    session: frida.core.Session | None = None
    script: frida.core.Script | None = None
    open_files: dict[int, OpenFileCapture] = {}
    saved_versions = 0

    def handle_sigint(signum: int, frame: Any) -> None:
        nonlocal stop
        stop = True
        print("\n[stop] signal received; detaching...", flush=True)

    signal.signal(signal.SIGINT, handle_sigint)

    def log_event(event: dict[str, Any]) -> None:
        with meta_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(event, ensure_ascii=False) + "\n")

    def save_capture(capture: OpenFileCapture, close_result: int) -> None:
        nonlocal saved_versions
        if capture.bytes_written <= 0:
            return
        saved_versions += 1
        stamp = current_stamp()
        path_name = sanitize_filename(Path(capture.path).name)
        out_name = f"{stamp}_{saved_versions:03d}_{path_name}"
        out_path = payload_dir / out_name
        data = b"".join(capture.chunks)
        out_path.write_bytes(data)
        event = {
            "ts": time.time(),
            "type": "saved_payload",
            "fd": capture.fd,
            "path": capture.path,
            "bytes_written": capture.bytes_written,
            "close_result": close_result,
            "output": str(out_path),
            "chunks": len(capture.chunks),
        }
        log_event(event)
        print(
            f"[save] {capture.path} -> {out_path.name} ({capture.bytes_written} bytes, {len(capture.chunks)} chunks)",
            flush=True,
        )

    def on_message(message: dict[str, Any], data: bytes | None) -> None:
        if message["type"] != "send":
            log_event({"ts": time.time(), "type": "frida_message", "message": message})
            print(f"[frida] {message}", flush=True)
            return

        payload = dict(message["payload"])
        payload["ts"] = time.time()
        kind = payload.get("type")

        if kind == "open":
            fd = int(payload["fd"])
            open_files[fd] = OpenFileCapture(
                fd=fd,
                path=payload["path"],
                open_ts=payload["ts"],
                via=payload.get("via"),
            )
            print(f"[open] fd={fd} path={payload['path']} via={payload.get('via')}", flush=True)
            log_event(payload)
            return

        if kind == "write":
            fd = int(payload["fd"])
            capture = open_files.get(fd)
            if capture is None:
                log_event(payload)
                return
            chunk = bytes(data or b"")
            capture.chunks.append(chunk)
            capture.bytes_written += len(chunk)
            payload["buffer_len"] = len(chunk)
            print(
                f"[write] fd={fd} actual={payload.get('actual')} total={capture.bytes_written} path={capture.path}",
                flush=True,
            )
            log_event(payload)
            return

        if kind == "close":
            fd = int(payload["fd"])
            capture = open_files.pop(fd, None)
            print(f"[close] fd={fd} path={payload.get('path')} result={payload.get('result')}", flush=True)
            log_event(payload)
            if capture is not None:
                save_capture(capture, int(payload.get("result", 0)))
            return

        print(f"[event] {payload}", flush=True)
        log_event(payload)

    device = frida.get_usb_device(timeout=5)
    print(f"[device] {device.name} ({device.type})", flush=True)
    process = wait_for_process(device, args.package, args.process_name, args.poll_seconds)
    print(f"[attach] pid={process.pid} name={process.name}", flush=True)

    summary = {
        "started_at": time.time(),
        "package": args.package,
        "device": device.name,
        "target_substring": args.target_substring,
        "page_marker": args.page_marker,
        "pid": process.pid,
    }
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    try:
        session = device.attach(process.pid)
        script = session.create_script(make_hook_source(args.target_substring, args.page_marker))
        script.on("message", on_message)
        script.load()
        print("[ready] hook loaded; запускай import в 2Books. Остановить: Ctrl+C", flush=True)

        while not stop:
            time.sleep(0.5)
    finally:
        for capture in list(open_files.values()):
            save_capture(capture, close_result=-999)
        open_files.clear()
        if script is not None:
            try:
                script.unload()
            except Exception:
                pass
        if session is not None:
            try:
                session.detach()
            except Exception:
                pass

        finished = {
            "finished_at": time.time(),
            "saved_versions": saved_versions,
        }
        with summary_path.open("a", encoding="utf-8") as fh:
            fh.write("\n")
            fh.write(json.dumps(finished, ensure_ascii=False, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
