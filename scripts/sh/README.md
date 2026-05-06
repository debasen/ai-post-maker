# Grok Home Automation Shell Script

A deterministic, fully automated shell script for generating image and video assets on Grok using `browseros-cli`.

## Prerequisites

- `browseros-cli` installed and initialized (`browseros-cli init --auto`)
- BrowserOS running (`browseros-cli health` passes)
- Python 3 available for tracker/downloader scripts
- Project structure: `project-<N>/grok_prompts.json`, `project-<N>/assets/current/`

## Installation

```bash
# Make scripts executable
chmod +x scripts/sh/grok_automation.sh
chmod +x scripts/sh/test/*.sh
```

## Usage

### Run a Single Project

```bash
./scripts/sh/grok_automation.sh --project 1
```

### Dry Run (Simulation Mode)

```bash
./scripts/sh/grok_automation.sh --dry-run --project 1
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--project <N>` | Project ID (1-4). **Required.** | - |
| `--dry-run` | Simulate all actions without executing. | false |
| `--log-dir <path>` | Directory for log files. | `./logs/` |
| `--timeout <seconds>` | Global timeout per phase. | 300 |
| `--max-retries <N>` | Max retries for flaky operations. | 3 |
| `--help` | Show help message. | - |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BROWSEROS_CLI` | Path to browseros-cli binary. | `browseros-cli` |
| `SELECTOR_INPUT` | CSS selector for Grok input area. | `div[contenteditable="true"]` |
| `SELECTOR_IMAGE` | CSS selector for generated image. | `img[alt="Generated image"]` |
| `SELECTOR_DOWNLOAD` | CSS selector for download button. | `[aria-label="Download"]` |
| `SELECTOR_MAKE_VIDEO` | CSS selector for make video button. | `[aria-label="Make video"]` |
| `LOG_LEVEL` | DEBUG, INFO, WARN, ERROR. | `INFO` |

## Workflow Phases

1. **Preparation** — Fetch next pending prompt from tracker.
2. **Platform Navigation** — Verify BrowserOS and navigate to Grok Imagine.
3. **Image Generation** — Type prompt, submit, wait for images.
4. **Video Generation** — Open image detail, click "Make video".
5. **Monitoring** — Poll for completion (Download/Thumbnail buttons).
6. **Asset Management** — Download, rename, verify file.
7. **Recording** — Update tracker with URLs.

## Testing

### Unit Tests

```bash
# Browser interaction helpers
./scripts/sh/test/test_browser.sh

# Tracker integration
./scripts/sh/test/test_tracker.sh
```

### End-to-End Dry-Run Test

```bash
./scripts/sh/test/test_e2e.sh
```

## Project Auto-Detection

| Project ID | Tracker | Downloader |
|------------|---------|------------|
| 1, 2, 4 | `grok_tracker.py` | `grok_video_downloader.py` |
| 3 | `grok_tracker_v3.py` | `grok_video_downloader_v3.py` |

## Troubleshooting

### BrowserOS Not Reachable
```bash
browseros-cli init --auto
browseros-cli launch
```

### Element Not Found
- Selectors may have changed. Override via environment variables:
  ```bash
  SELECTOR_INPUT='div[contenteditable="true"]' ./scripts/sh/grok_automation.sh --project 1
  ```
- Check logs for DOM snapshots saved as artifacts.

### Download Fails
- The script automatically falls back to `curl` if `browseros-cli download` fails.
- Ensure the destination directory exists and is writable.

### Video Generation Timeout
- Increase timeout: `./scripts/sh/grok_automation.sh --project 1 --timeout 600`
- Check Grok UI for generation progress manually.

## Logs

All logs are written to `logs/grok_automation_YYYYMMDD_HHMMSS.log`. Each run creates a new log file. Logs include:
- Timestamps for every action
- Command output and exit codes
- Phase boundaries
- Artifact snapshots (DOM structure, eval results)
