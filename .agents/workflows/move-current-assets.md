---
description: Move Current Assets
---

# Move Current Assets

Move `.mp4` files from `project-<N>/assets/current/` to `project-<N>/assets/` and mark the corresponding prompt record as `instagram_upload=mapped`.

## Usage

```
/move-current-assets --project <1|2|3|4> [--dry-run]
```

## Examples

```
/move-current-assets --project 1
/move-current-assets --project 2 --dry-run
```

## Implementation

Run the `scripts/py/move_current_assets.py` script with the provided arguments.
