from __future__ import annotations

import json
import socket
import traceback
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from .storage import LexoStorage


ROOT = Path(__file__).resolve().parent.parent
STORAGE = LexoStorage(ROOT)
BODY_STREAM_CHUNK_SIZE = 64 * 1024


class LexoHandler(BaseHTTPRequestHandler):
    server_version = "LEXOEngine/0.2"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        print(f"[LEXO ENGINE] GET {path}")
        try:
            if path == "/health":
                self._send_json(HTTPStatus.OK, {"ok": True, "service": "lexo-engine"})
                return
            if path == "/books":
                self._send_json(HTTPStatus.OK, STORAGE.list_books())
                return
            if path == "/book":
                self._send_json(HTTPStatus.OK, STORAGE.get_book_status(_query_value(query, "book_id")))
                return
            if path == "/reader/paragraphs":
                self._send_json(
                    HTTPStatus.OK,
                    STORAGE.get_paragraphs(_query_value(query, "book_id")),
                )
                return
            if path == "/reader/detail-sheet":
                self._send_json(
                    HTTPStatus.OK,
                    STORAGE.get_detail_sheet(
                        _query_value(query, "book_id") or "",
                        _query_value(query, "word_id") or "",
                    ),
                )
                return
            if path == "/saved-words":
                self._send_json(HTTPStatus.OK, STORAGE.list_saved_words())
                return
            if path == "/cards":
                self._send_json(
                    HTTPStatus.OK,
                    STORAGE.list_saved_cards(_query_value(query, "status")),
                )
                return
            if path == "/cards/review":
                self._send_json(HTTPStatus.OK, STORAGE.get_review_cards())
                return
            if path == "/tts/profiles":
                self._send_json(HTTPStatus.OK, STORAGE.get_tts_profiles())
                return
            if path == "/tts/levels":
                self._send_json(HTTPStatus.OK, STORAGE.get_tts_levels())
                return
            if path == "/tts/state":
                self._send_json(
                    HTTPStatus.OK,
                    STORAGE.get_tts_state(_query_value(query, "book_id")),
                )
                return
            if path == "/mobile/desktop-books":
                self._send_json(HTTPStatus.OK, STORAGE.list_books())
                return
            if path == "/mobile/books/package":
                book_id = _query_value(query, "book_id") or ""
                payload = STORAGE.build_mobile_book_package(book_id)
                payload_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                print(f"[LEXO ENGINE] MOBILE_PACKAGE book_id={book_id} bytes={len(payload_bytes)}")
                self._send_json(HTTPStatus.OK, payload)
                return
            if path == "/mobile/books/audio":
                book_id = _query_value(query, "book_id") or ""
                job_id = _query_value(query, "job_id") or ""
                segment_index = int(_query_value(query, "segment_index") or "0")
                audio_path = STORAGE.get_tts_audio_path(
                    book_id,
                    job_id,
                    segment_index,
                )
                print(
                    "[LEXO ENGINE] MOBILE_AUDIO "
                    f"book_id={book_id} job_id={job_id} segment_index={segment_index} "
                    f'path="{audio_path}" bytes={audio_path.stat().st_size}'
                )
                self._send_file(HTTPStatus.OK, audio_path, "audio/wav")
                return
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
        except Exception as exc:  # pragma: no cover
            print(f"[LEXO ENGINE] GET {path} failed: {exc}")
            traceback.print_exc()
            self._try_send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        payload = self._read_json_body()
        print(f"[LEXO ENGINE] POST {path} payload={payload}")
        try:
            if path == "/books/import":
                result = STORAGE.import_book(
                    payload["source_path"],
                    source_lang=payload.get("source_lang", "en"),
                    target_lang=payload.get("target_lang", "ru"),
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/books/import-text":
                result = STORAGE.import_book_text(
                    payload["title"],
                    payload["source_text"],
                    source_lang=payload.get("source_lang", "en"),
                    target_lang=payload.get("target_lang", "ru"),
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/mobile/books/import-text":
                result = STORAGE.import_book_text(
                    payload["title"],
                    payload["source_text"],
                    source_lang=payload.get("source_lang", "en"),
                    target_lang=payload.get("target_lang", "ru"),
                )
                self._send_json(HTTPStatus.OK, STORAGE.build_mobile_book_package(result["id"]))
                return
            if path == "/books/open":
                result = STORAGE.set_active_book(payload["book_id"])
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/books/delete":
                result = STORAGE.delete_book(payload["book_id"])
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/reader/position":
                result = STORAGE.save_reader_position(
                    payload["book_id"],
                    int(payload["paragraph_index"]),
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/reader/detail-sheet/save":
                result = STORAGE.save_detail_unit(
                    payload["book_id"],
                    payload["word_id"],
                    payload["unit_id"],
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/tts/generate":
                level_ids = payload.get("level_ids") or payload.get("levels") or []
                result = STORAGE.generate_tts_jobs(
                    book_id=payload["book_id"],
                    voice_id=payload["voice_id"],
                    level_ids=[int(item) for item in level_ids],
                    mode=payload.get("mode", "play_from_current"),
                    overwrite=bool(payload.get("overwrite", False)),
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/tts/start":
                result = STORAGE.start_tts_job(
                    book_id=payload["book_id"],
                    job_id=payload["job_id"],
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/tts/control":
                result = STORAGE.control_tts(payload["book_id"], payload["job_id"], payload["action"])
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/saved-words":
                result = STORAGE.save_detail_unit(
                    payload["book_id"],
                    payload["word_id"],
                    payload["unit_id"],
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/cards/review/result":
                result = STORAGE.apply_review_result(
                    payload["card_id"],
                    payload["direction"],
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/cards/delete":
                result = STORAGE.delete_saved_card(payload["card_id"])
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/mobile/sync/full":
                result = STORAGE.sync_mobile_cards_full(
                    device_id=payload["device_id"],
                    cards_delta=payload.get("cards_delta") or [],
                    last_sync_at=payload.get("last_sync_at"),
                )
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/mobile/debug/log":
                tag = str(payload.get("tag") or "MOBILE_DEBUG").strip() or "MOBILE_DEBUG"
                message = str(payload.get("message") or "").strip()
                print(f"[LEXO {tag}] {message}")
                self._send_json(HTTPStatus.OK, {"ok": True})
                return
            if path == "/saved-words/raw":
                result = STORAGE.save_raw_word(payload["word"])
                self._send_json(HTTPStatus.OK, result)
                return
            if path == "/word/audio":
                self._send_json(HTTPStatus.OK, {"audio_path": "stub://word-audio"})
                return
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
        except KeyError as exc:
            print(f"[LEXO ENGINE] POST {path} bad request: missing {exc.args[0]}")
            self._try_send_json(HTTPStatus.BAD_REQUEST, {"error": f"Missing field: {exc.args[0]}"})
        except (ValueError, FileNotFoundError) as exc:
            print(f"[LEXO ENGINE] POST {path} bad request: {exc}")
            self._try_send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        except Exception as exc:  # pragma: no cover
            print(f"[LEXO ENGINE] POST {path} failed: {exc}")
            traceback.print_exc()
            self._try_send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    def _read_json_body(self) -> dict:
        content_length = self.headers.get("Content-Length")
        transfer_encoding = self.headers.get("Transfer-Encoding")
        if transfer_encoding and transfer_encoding.lower() == "chunked":
            raw_bytes = self._read_chunked_body()
        else:
            length = int(content_length or "0")
            if length == 0:
                return {}
            raw_bytes = self.rfile.read(length)
        return json.loads(raw_bytes.decode("utf-8"))

    def _read_chunked_body(self) -> bytes:
        chunks: list[bytes] = []
        while True:
            line = self.rfile.readline()
            if not line:
                break
            chunk_size = int(line.strip().split(b";", 1)[0], 16)
            if chunk_size == 0:
                self.rfile.readline()
                break
            chunks.append(self.rfile.read(chunk_size))
            self.rfile.read(2)
        return b"".join(chunks)

    def _send_json(self, status: HTTPStatus, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self._write_body(body, label=f"JSON {self.command} {self.path}")

    def _send_file(self, status: HTTPStatus, path: Path, content_type: str) -> None:
        body = path.read_bytes()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self._write_file_body(body, label=f"FILE {self.command} {self.path}")

    def _try_send_json(self, status: HTTPStatus, payload: dict) -> None:
        try:
            self._send_json(status, payload)
        except Exception as send_exc:  # pragma: no cover
            print(f"[LEXO ENGINE] Failed to send error response for {self.path}: {send_exc}")
            traceback.print_exc()
            self.close_connection = True

    def _write_body(self, body: bytes, *, label: str) -> None:
        self._write_chunks(
            _iter_bytes(body, BODY_STREAM_CHUNK_SIZE),
            len(body),
            label=label,
        )

    def _write_file_body(self, body: bytes, *, label: str) -> None:
        bytes_sent = 0
        try:
            self.wfile.write(body)
            self.wfile.flush()
            bytes_sent = len(body)
            self.close_connection = True
            print(f"[LEXO ENGINE] RESPONSE_OK {label} bytes={bytes_sent}/{len(body)}")
        except (BrokenPipeError, ConnectionResetError, TimeoutError, socket.timeout, OSError) as exc:
            self.close_connection = True
            print(
                f"[LEXO ENGINE] RESPONSE_ABORTED {label} bytes={bytes_sent}/{len(body)} "
                f"error={exc.__class__.__name__}: {exc}"
            )
            raise

    def _write_chunks(self, chunks, total_size: int, *, label: str) -> None:
        bytes_sent = 0
        try:
            for chunk in chunks:
                self.wfile.write(chunk)
                self.wfile.flush()
                bytes_sent += len(chunk)
            self.close_connection = True
            print(f"[LEXO ENGINE] RESPONSE_OK {label} bytes={bytes_sent}/{total_size}")
        except (BrokenPipeError, ConnectionResetError, TimeoutError, socket.timeout, OSError) as exc:
            self.close_connection = True
            print(
                f"[LEXO ENGINE] RESPONSE_ABORTED {label} bytes={bytes_sent}/{total_size} "
                f"error={exc.__class__.__name__}: {exc}"
            )
            raise

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def log_message(self, format: str, *args) -> None:
        return


def run(host: str = "127.0.0.1", port: int = 8765) -> None:
    server = ThreadingHTTPServer((host, port), LexoHandler)
    print(f"LEXO engine running at http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def _query_value(query: dict[str, list[str]], key: str) -> str | None:
    values = query.get(key)
    return values[0] if values else None


def _iter_bytes(body: bytes, chunk_size: int):
    for offset in range(0, len(body), chunk_size):
        yield body[offset : offset + chunk_size]
