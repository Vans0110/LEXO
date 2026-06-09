# Virgil Workbench

Run:

```text
run_virgil_workbench.bat
```

The launcher starts `Studio/Backend/run_backend.bat` when needed and opens the
Windows Workbench from `Virgil/App`.

## Paths

- `Books/` - source TXT files and covers.
- `../Runtime/workbench_output/` - generated package folders and ZIP files.
- `../CloudLibrary/` - local R2 catalog mirror.
- `../Backend/data/` - backend databases, models, dictionaries and TTS cache.

Publishing from Workbench rebuilds `Studio/CloudLibrary/library_index.json` and
uploads files to R2 in the existing three-phase order.

If Windows Flutter caches become invalid after a move, run:

```text
run_virgil_workbench_clean.bat
```
