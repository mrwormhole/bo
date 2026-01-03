# Scripts

## Verify Man Page

Verify that the embedded man page matches the original groff-formatted output:

```bash
scripts/verify_man_page.py
```

## Compare Man Page Outputs

Compare the current implementation with the latest upstream groff-formatted output:

```bash
./scripts/generate_full_man.py
```

Files created in `/tmp/`:

- `original_tree.1` - Downloaded man page source
- `original_formatted.txt` - Expected formatted output
- `current_formatted.txt` - Current `tree man` output

## How to Regenerate `man.zig` File

To update `src/man.zig` with the latest upstream man page:

```bash
# Download, format, and regenerate src/man.zig
./scripts/generate_full_man.py --write

# Verify it matches
./scripts/verify_man_page.py
```
