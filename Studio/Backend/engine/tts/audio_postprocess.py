from __future__ import annotations

from array import array
import json
import wave
from pathlib import Path


def expand_word_gaps_in_place(
    *,
    audio_path: Path,
    timings_path: Path,
    min_gap_ms: int,
) -> int:
    if min_gap_ms <= 0:
        return _read_duration_ms(audio_path)
    timings = _read_timings(timings_path)
    if len(timings) < 2:
        return _read_duration_ms(audio_path)

    with wave.open(str(audio_path), "rb") as wav_file:
        params = wav_file.getparams()
        sample_rate = wav_file.getframerate() or 24000
        sample_width = wav_file.getsampwidth()
        channels = wav_file.getnchannels()
        frame_count = wav_file.getnframes()
        pcm = wav_file.readframes(frame_count)

    if sample_width != 2 or channels != 1:
        return _read_duration_ms(audio_path)

    frame_size = sample_width * channels
    min_gap_frames = _seconds_to_frames(min_gap_ms / 1000.0, sample_rate)
    fade_frames = _seconds_to_frames(0.015, sample_rate)
    pre_pad_frames = _seconds_to_frames(0.010, sample_rate)
    post_pad_frames = _seconds_to_frames(0.015, sample_rate)
    pcm_samples = array("h")
    pcm_samples.frombytes(pcm)

    token_specs = _build_token_specs(
        timings,
        sample_rate,
        pre_pad_frames=pre_pad_frames,
        post_pad_frames=post_pad_frames,
    )
    if not token_specs:
        return _read_duration_ms(audio_path)

    first_slice_start = token_specs[0]["slice_start_frame"]
    output = bytearray()
    output.extend(_slice_samples(pcm_samples, 0, first_slice_start).tobytes())
    output_frame_cursor = max(0, first_slice_start)

    rebuilt_timings: list[dict] = []
    token_slices = [
        _slice_samples(
            pcm_samples,
            int(spec["slice_start_frame"]),
            int(spec["slice_end_frame"]),
        )
        for spec in token_specs
    ]

    for index, spec in enumerate(token_specs):
        token_slice = array("h", token_slices[index])
        output.extend(token_slice.tobytes())
        token_start_frame = output_frame_cursor + int(spec["pre_roll_frames"])
        token_end_frame = token_start_frame + int(spec["word_frames"])
        rebuilt_timings.append(
            {
                **spec["timing"],
                "start": round(token_start_frame / sample_rate, 4),
                "end": round(token_end_frame / sample_rate, 4),
            }
        )
        output_frame_cursor += len(token_slice)
        if index >= len(token_specs) - 1:
            continue
        original_gap_frames = int(spec["gap_to_next_frames"])
        extra_gap_frames = max(0, min_gap_frames - original_gap_frames)
        if extra_gap_frames > 0:
            next_slice = token_slices[index + 1]
            effective_fade_frames = min(
                fade_frames,
                len(token_slice),
                len(next_slice),
            )
            if effective_fade_frames > 0:
                _fade_out_tail(output, effective_fade_frames)
                _fade_in_head(next_slice, effective_fade_frames)
                token_slices[index + 1] = next_slice
            output.extend(b"\x00" * (extra_gap_frames * frame_size))
            output_frame_cursor += extra_gap_frames

    last_slice_end = int(token_specs[-1]["slice_end_frame"])
    if last_slice_end < frame_count:
        output.extend(_slice_samples(pcm_samples, last_slice_end, frame_count).tobytes())

    with wave.open(str(audio_path), "wb") as wav_file:
        wav_file.setparams(params)
        wav_file.writeframes(bytes(output))

    timings_path.write_text(
        json.dumps(rebuilt_timings, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return int((len(output) / frame_size) / sample_rate * 1000)


def _read_timings(path: Path) -> list[dict]:
    if not path.exists() or not path.is_file():
        return []
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        return []
    result: list[dict] = []
    for item in payload:
        if isinstance(item, dict) and "start" in item and "end" in item:
            result.append(item)
    return result


def _build_token_specs(
    timings: list[dict],
    sample_rate: int,
    *,
    pre_pad_frames: int,
    post_pad_frames: int,
) -> list[dict]:
    specs: list[dict] = []
    frames = []
    for timing in timings:
        start_frame = _seconds_to_frames(float(timing["start"]), sample_rate)
        end_frame = _seconds_to_frames(float(timing["end"]), sample_rate)
        if end_frame < start_frame:
            end_frame = start_frame
        frames.append((start_frame, end_frame))
    for index, timing in enumerate(timings):
        start_frame, end_frame = frames[index]
        padded_start_frame = max(0, start_frame - pre_pad_frames)
        padded_end_frame = max(padded_start_frame, end_frame + post_pad_frames)
        if index == 0:
            slice_start_frame = padded_start_frame
        else:
            previous_end = frames[index - 1][1]
            previous_midpoint = (previous_end + start_frame) // 2
            slice_start_frame = max(previous_midpoint, padded_start_frame)
        if index >= len(frames) - 1:
            slice_end_frame = padded_end_frame
            gap_to_next_frames = 0
        else:
            next_start = frames[index + 1][0]
            next_midpoint = (end_frame + next_start) // 2
            slice_end_frame = min(next_midpoint, padded_end_frame)
            gap_to_next_frames = max(0, next_start - end_frame)
        if slice_end_frame < slice_start_frame:
            slice_end_frame = slice_start_frame
        specs.append(
            {
                "timing": timing,
                "slice_start_frame": slice_start_frame,
                "slice_end_frame": slice_end_frame,
                "pre_roll_frames": max(0, start_frame - slice_start_frame),
                "word_frames": max(0, end_frame - start_frame),
                "gap_to_next_frames": gap_to_next_frames,
            }
        )
    return specs


def _slice_samples(samples: array, start_frame: int, end_frame: int) -> array:
    clamped_start = max(0, start_frame)
    clamped_end = max(clamped_start, end_frame)
    return array("h", samples[clamped_start:clamped_end])


def _fade_out_tail(output: bytearray, fade_frames: int) -> None:
    if fade_frames <= 0:
        return
    sample_count = min(fade_frames, len(output) // 2)
    if sample_count <= 0:
        return
    faded = array("h")
    faded.frombytes(output[-sample_count * 2 :])
    for index in range(sample_count):
        gain = (sample_count - index) / sample_count
        faded[index] = int(faded[index] * gain)
    output[-sample_count * 2 :] = faded.tobytes()


def _fade_in_head(samples: array, fade_frames: int) -> None:
    sample_count = min(fade_frames, len(samples))
    if sample_count <= 0:
        return
    for index in range(sample_count):
        gain = index / sample_count
        samples[index] = int(samples[index] * gain)


def _seconds_to_frames(seconds: float, sample_rate: int) -> int:
    return max(0, int(round(seconds * sample_rate)))


def _read_duration_ms(audio_path: Path) -> int:
    with wave.open(str(audio_path), "rb") as wav_file:
        frame_count = wav_file.getnframes()
        sample_rate = wav_file.getframerate() or 24000
    return int(frame_count / sample_rate * 1000)
