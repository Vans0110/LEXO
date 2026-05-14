from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = ROOT / "tmp" / "2books_tap_runs"
DEFAULT_MANIFEST = {
    "book": "The Bus Driver",
    "page": 0,
    "notes": "Fill x/y from your emulator layout before running.",
    "taps": [
        {"label": "The", "x": 0, "y": 0},
        {"label": "Bus", "x": 0, "y": 0},
        {"label": "Driver", "x": 0, "y": 0},
        {"label": "is", "x": 0, "y": 0},
        {"label": "a", "x": 0, "y": 0},
        {"label": "up", "x": 0, "y": 0},
        {"label": "in_city", "x": 0, "y": 0},
        {"label": "on_bus", "x": 0, "y": 0},
        {"label": "There", "x": 0, "y": 0},
        {"label": "to", "x": 0, "y": 0},
    ],
}


@dataclass
class TapCase:
    label: str
    x: int
    y: int
    wait_ms: int = 900
    note: str = ""


@dataclass
class TapResult:
    label: str
    x: int
    y: int
    wait_ms: int
    note: str
    screenshot: str
    xml_dump: str | None
    captured_at_utc: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture 2Books tap #1 screenshots for a prepared list of word coordinates."
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=None,
        help="JSON file with taps: {book, page, taps:[{label,x,y,wait_ms?,note?}]}",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory where one run folder with screenshots and manifest will be created.",
    )
    parser.add_argument(
        "--adb-path",
        type=str,
        default="adb",
        help="Path to adb executable. Example: C:\\Users\\Ivan\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe",
    )
    parser.add_argument(
        "--serial",
        type=str,
        default="",
        help="Optional adb device serial, for example emulator-5554.",
    )
    parser.add_argument(
        "--pre-delay-ms",
        type=int,
        default=1500,
        help="Delay before the first tap, to let you focus the app.",
    )
    parser.add_argument(
        "--post-delay-ms",
        type=int,
        default=300,
        help="Extra delay after each screenshot before the next tap.",
    )
    parser.add_argument(
        "--dump-xml",
        action="store_true",
        help="Also run uiautomator dump after each tap and save the XML next to the screenshot.",
    )
    parser.add_argument(
        "--write-template",
        type=Path,
        default=None,
        help="Write a template manifest JSON and exit.",
    )
    return parser.parse_args()


def resolve_adb(adb_path: str) -> str:
    if Path(adb_path).exists():
        return adb_path
    resolved = shutil.which(adb_path)
    if resolved:
        return resolved
    raise FileNotFoundError(f"adb not found: {adb_path}")


def adb_base_command(adb_path: str, serial: str) -> list[str]:
    cmd = [adb_path]
    if serial:
        cmd.extend(["-s", serial])
    return cmd


def run_command(cmd: list[str], *, capture_output: bool = False) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(cmd, check=True, capture_output=capture_output)


def adb_shell(adb_path: str, serial: str, shell_cmd: str) -> None:
    run_command(adb_base_command(adb_path, serial) + ["shell", shell_cmd])


def adb_pull(adb_path: str, serial: str, remote_path: str, local_path: Path) -> None:
    local_path.parent.mkdir(parents=True, exist_ok=True)
    run_command(adb_base_command(adb_path, serial) + ["pull", remote_path, str(local_path)])


def load_tap_cases(manifest_path: Path) -> tuple[dict[str, Any], list[TapCase]]:
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    taps = payload.get("taps")
    if not isinstance(taps, list) or not taps:
        raise ValueError("Manifest must contain non-empty taps array.")
    cases: list[TapCase] = []
    for index, item in enumerate(taps):
        if not isinstance(item, dict):
            raise ValueError(f"Tap #{index} is not an object.")
        label = str(item.get("label") or "").strip()
        if not label:
            raise ValueError(f"Tap #{index} is missing label.")
        x = int(item.get("x"))
        y = int(item.get("y"))
        wait_ms = int(item.get("wait_ms", 900))
        note = str(item.get("note") or "")
        cases.append(TapCase(label=label, x=x, y=y, wait_ms=wait_ms, note=note))
    return payload, cases


def write_template(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(DEFAULT_MANIFEST, ensure_ascii=False, indent=2), encoding="utf-8")


def utc_now_compact() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def make_run_dir(base_output_dir: Path) -> Path:
    run_dir = base_output_dir / f"run_{utc_now_compact()}"
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def sanitize_label(label: str) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in {"-", "_"} else "_" for ch in label)
    return cleaned.strip("_") or "tap"


def capture_screen(adb_path: str, serial: str, dest: Path) -> None:
    remote = "/sdcard/2books_tap_capture.png"
    adb_shell(adb_path, serial, f"rm -f {remote}")
    adb_shell(adb_path, serial, f"screencap -p {remote}")
    adb_pull(adb_path, serial, remote, dest)
    adb_shell(adb_path, serial, f"rm -f {remote}")


def capture_xml_dump(adb_path: str, serial: str, dest: Path) -> None:
    remote = "/sdcard/2books_ui.xml"
    adb_shell(adb_path, serial, f"rm -f {remote}")
    adb_shell(adb_path, serial, f"uiautomator dump {remote}")
    adb_pull(adb_path, serial, remote, dest)
    adb_shell(adb_path, serial, f"rm -f {remote}")


def perform_tap_run(
    *,
    adb_path: str,
    serial: str,
    cases: list[TapCase],
    run_dir: Path,
    dump_xml: bool,
    pre_delay_ms: int,
    post_delay_ms: int,
) -> list[TapResult]:
    screenshots_dir = run_dir / "screenshots"
    screenshots_dir.mkdir(parents=True, exist_ok=True)
    xml_dir = run_dir / "ui_xml"
    if dump_xml:
        xml_dir.mkdir(parents=True, exist_ok=True)

    time.sleep(pre_delay_ms / 1000.0)
    results: list[TapResult] = []

    for index, case in enumerate(cases, start=1):
        adb_shell(adb_path, serial, f"input tap {case.x} {case.y}")
        time.sleep(case.wait_ms / 1000.0)

        stem = f"{index:02d}_{sanitize_label(case.label)}"
        screenshot_path = screenshots_dir / f"{stem}.png"
        capture_screen(adb_path, serial, screenshot_path)

        xml_path: Path | None = None
        if dump_xml:
            xml_path = xml_dir / f"{stem}.xml"
            capture_xml_dump(adb_path, serial, xml_path)

        results.append(
            TapResult(
                label=case.label,
                x=case.x,
                y=case.y,
                wait_ms=case.wait_ms,
                note=case.note,
                screenshot=str(screenshot_path.relative_to(run_dir)),
                xml_dump=str(xml_path.relative_to(run_dir)) if xml_path else None,
                captured_at_utc=utc_now_iso(),
            )
        )
        time.sleep(post_delay_ms / 1000.0)

    return results


def main() -> None:
    args = parse_args()
    if args.write_template:
        write_template(args.write_template)
        print(f"Template written to {args.write_template}")
        return

    if args.manifest is None:
        raise SystemExit("Pass --manifest or use --write-template first.")

    adb_path = resolve_adb(args.adb_path)
    payload, cases = load_tap_cases(args.manifest)
    run_dir = make_run_dir(args.output_dir)

    results = perform_tap_run(
        adb_path=adb_path,
        serial=args.serial,
        cases=cases,
        run_dir=run_dir,
        dump_xml=args.dump_xml,
        pre_delay_ms=args.pre_delay_ms,
        post_delay_ms=args.post_delay_ms,
    )

    summary = {
        "book": payload.get("book", ""),
        "page": payload.get("page", 0),
        "notes": payload.get("notes", ""),
        "adb_path": adb_path,
        "serial": args.serial,
        "pre_delay_ms": args.pre_delay_ms,
        "post_delay_ms": args.post_delay_ms,
        "dump_xml": args.dump_xml,
        "created_at_utc": utc_now_iso(),
        "results": [asdict(item) for item in results],
    }
    manifest_copy = run_dir / "input_manifest.json"
    manifest_copy.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    result_manifest = run_dir / "run_manifest.json"
    result_manifest.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Run saved to {run_dir}")
    for item in results:
        print(f"{item.label}: {item.screenshot}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        print(f"Command failed: {' '.join(exc.cmd)}", file=sys.stderr)
        raise
