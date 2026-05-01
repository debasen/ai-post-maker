# Grok Automation v2 — Issues, Gaps, Challenges & Edge Cases

> **Scope**: Workflow definition (`.agents/workflows/grok_automation_v2.md`), source JS (`scripts/js/grok_automation_v2.js`), and minified JS (`scripts/js/grok_automation_v2.min.js`)  
> **Date**: 2026-05-01

---

## Table of Contents

1. [Critical Issues](#1-critical-issues)
2. [Workflow-Code Gaps](#2-workflow-code-gaps)
3. [Error Handling & Resilience](#3-error-handling--resilience)
4. [Race Conditions & Timing](#4-race-conditions--timing)
5. [Selector Fragility](#5-selector-fragility)
6. [Retry Logic Limitations](#6-retry-logic-limitations)
7. [State Management & Persistence](#7-state-management--persistence)
8. [Edge Cases in Video/Extend Flow](#8-edge-cases-in-videoextend-flow)
9. [False Positives in Detection](#9-false-positives-in-detection)
10. [Operational & Observability Gaps](#10-operational--observability-gaps)

---

## 1. Critical Issues

### 1.1 Source vs Minified Mismatch Risk
- **Issue**: The workflow loads `scripts/js/grok_automation_v2.min.js`, but the readable source is `scripts/js/grok_automation_v2.js`. There is no build script or CI check ensuring the minified file stays in sync with the source.
- **Impact**: Developers may edit the source and forget to regenerate the minified file, causing the workflow to run stale code.
- **Mitigation**: Add a build step (`npm run build` or a `Makefile`) that regenerates `.min.js` from `.js`, and/or add a CI check that fails if the minified file is out of sync.

### 1.2 Missing `selectBestImage` in Workflow Documentation
- **Issue**: `triggerVideoGeneration()` internally calls `selectBestImage()`, which can return `image_failed` (e.g., all images moderated after "Generate More"). The workflow's Step 4 documents this return value but does not mention `selectBestImage` as a sub-step.
- **Impact**: Operators reading the workflow may not understand why Step 4 can fail with `image_failed` even when Step 3 succeeded.
- **Mitigation**: Add `selectBestImage` as an explicit sub-step in Step 4.
- Answer: selectBestImage should be decided by the AI by taking a screenshot of the page and decide which index to pick. Based on which is realistic, best match the description and most appealing.

### 1.3 `postUrl` Loss on Page Crash/Navigation
- **Issue**: `postUrl` is captured as `window.location.href` at various points. If the page crashes, reloads, or navigates unexpectedly, the original `postUrl` may be lost before the tracker can be updated.
- **Impact**: Records may be marked with incorrect or missing `post_url`, making them hard to trace.
- **Mitigation**: Cache `postUrl` in a persistent variable at the earliest possible point (immediately after image generation) and never reassign it.
- Answer: Post url is available only after clicking on an image.

---

## 2. Workflow-Code Gaps

### 2.1 Undocumented `spicy` Mode
- **Gap**: The JS supports `mode === 'spicy'` (lines 324–368), but the workflow only documents `custom_video_prompt` and `default_make_video`.
- **Impact**: If a caller passes `spicy`, the workflow documentation provides no guidance on expected behavior or retry rules.
- **Mitigation**: Document `spicy` mode in the workflow or remove it from the JS if unsupported.

### 2.2 Undocumented `automateGrokGenerationV2` Function
- **Gap**: The JS exports `automateGrokGenerationV2` (line 236), but the workflow only uses `generateGrokImages`.
- **Impact**: Confusion about which entry point is canonical.
- **Mitigation**: Deprecate or document `automateGrokGenerationV2`.

### 2.3 Step 7 Download Assumes Static `aria-label`
- **Gap**: The workflow instructs finding `aria-label="Download"`, but the JS also checks for `pauseBtn` as a success indicator. There is no handling if the download button has a different label or is absent.
- **Impact**: Download step may fail on UI changes.
- **Mitigation**: Add fallback selectors or use the video element's `src` to programmatically download the file.
- Answer: Ignore

---

## 3. Error Handling & Resilience

### 3.1 No Handling for CAPTCHA / Human Verification
- **Issue**: If Grok presents a CAPTCHA, rate-limit screen, or login wall, the script has no detection logic.
- **Impact**: All polling loops will eventually time out, and the record will be incorrectly marked `failed` or `video_failed`.
- **Mitigation**: Add CAPTCHA detection patterns (e.g., `iframe[src*="captcha"]`, `text.includes("verify you are human")`) and exit with a new terminal status like `human_required`.

### 3.2 No Network Disconnection Handling
- **Issue**: If the network drops, `fetch`/page loads stall. The script only detects this via timeout.
- **Impact**: False negatives — records marked as failed due to transient network issues.
- **Mitigation**: Add a `navigator.onLine` check at the start of each major step, or detect "No internet" browser error pages.

### 3.3 No Handling for 5xx / Grok Internal Errors
- **Issue**: `detectVideoFailure` scans for text patterns but may not catch generic "Something went wrong" or 500-error pages.
- **Impact**: Script may hang or misclassify the failure.
- **Mitigation**: Add detection for generic error banners and HTTP status indicators.

### 3.4 `triggerVideoGeneration` Doesn't Distinguish Failure Types
- **Issue**: In Step 4B, the workflow tones down the prompt and retries. But if the failure was a network error or Grok internal error (not moderation), a toned-down prompt won't help.
- **Impact**: Wasted retry that will likely fail again.
- **Mitigation**: Categorize failures into `moderation`, `transient`, and `permanent`. Only apply tone-down on moderation failures.

---

## 4. Race Conditions & Timing

### 4.1 `selectBestImage` — Fixed 2s Wait After Click
- **Issue**: After clicking the best card, the code waits a hardcoded 2000ms (line 307). If the detail view takes longer to load (slow network, heavy page), the subsequent steps will operate on the wrong page.
- **Impact**: `triggerVideoGeneration` may fail to find the "Make video" button because it's still on the grid view.
- **Mitigation**: Poll for the presence of the "Make video" button or a URL change instead of a fixed wait.

### 4.2 `clickElement` — No Visibility/Overlay Check
- **Issue**: `clickElement` dispatches pointer/mouse events but does not verify the element is not covered by another element or outside the viewport.
- **Impact**: Clicks may be intercepted by overlays, modals, or cookies banners, causing silent failures.
- **Mitigation**: Use `element.checkVisibility()` and verify `document.elementFromPoint()` matches the target before clicking.

### 4.3 `generateMoreImages` — Waits for `cards.length > 4`
- **Issue**: The function waits for strictly more than 4 cards (line 139). If Grok replaces the existing 4 cards with 4 new ones (instead of appending), the count stays at 4 and the function times out.
- **Impact**: Unnecessary fallback to `image_failed`.
- **Mitigation**: Track card identifiers (e.g., `src` attributes) to detect replacement, not just count.

### 4.4 `waitForUrlChange` — Misses Hash/Query-Only Changes
- **Issue**: The function only checks `window.location.href !== oldUrl` (line 430). If Grok uses hash-based SPA routing (e.g., `/#/imagine/abc` → `/#/imagine/def`), the comparison works, but if it only changes a query param or uses `history.replaceState`, the change might be missed or incorrectly detected.
- **Impact**: False `urlChanged: false` results.
- **Mitigation**: Also poll for the presence of expected UI elements (video player, pause button) as a secondary signal.

---

## 5. Selector Fragility

### 5.1 `promptInput` Relies on `ProseMirror` Class
- **Issue**: `div[contenteditable="true"].ProseMirror` is hardcoded. If Grok updates its rich-text editor library, this selector breaks.
- **Impact**: Entire automation fails at Step 3.
- **Mitigation**: Add fallback selectors (e.g., `[contenteditable="true"]`, `textarea`, `role="textbox"`) and validate the element is visible before using it.

### 5.2 `submitBtn` — Brittle `aria-label` List
- **Issue**: The selector checks `Submit`, `Grok`, `Send`, `Edit`. If Grok renames the button to `Generate` or `Create`, the selector fails.
- **Impact**: Prompt submission fails.
- **Mitigation**: Use a broader selector (e.g., `button[type="submit"]`, last visible button in the input area) with the `aria-label` list as a fallback.

### 5.3 `imageCard` — Class Name Contains `media-post-masonry-card`
- **Issue**: This is a generated CSS class name. If the build hash changes, the selector breaks.
- **Impact**: Image generation polling never detects completion.
- **Mitigation**: Use structural selectors (e.g., `img[src*="imagine-public"]` inside a grid container) alongside the class name.

### 5.4 `spicyMenuItem`, `extendMenuItem`, `normalMenuItem` — XPath Text Matching
- **Issue**: XPath selectors that match on text content (`contains(., 'Extend')`) are sensitive to localization or UI text changes.
- **Impact**: Extend and Spicy features break silently.
- **Mitigation**: Use `aria-label` or data-attribute selectors where possible, with text content as a fallback.

---

## 6. Retry Logic Limitations

### 6.1 Only One Retry for Image Moderation
- **Issue**: If the toned-down prompt is also moderated, the record is immediately marked `failed`.
- **Impact**: No gradual de-escalation (e.g., second, more conservative tone-down).
- **Mitigation**: Consider allowing 2 retries with progressively more conservative tone-down rules.

### 6.2 No Retry for `image_failed` Due to Timeout
- **Issue**: If image generation exceeds 60 attempts (120 seconds), it's marked `failed` with no retry.
- **Impact**: False failures on slow Grok servers.
- **Mitigation**: Distinguish between "moderated" and "timeout" failures. Allow a single retry with extended polling on timeout.

### 6.3 Step 4B — No Retry for `default_make_video` Failures
- **Issue**: If the original mode was `default_make_video` (no `video_prompt`), Step 4B immediately marks the record `video_failed` because there's nothing to tone down.
- **Impact**: A video failure that might have succeeded on retry (e.g., transient error) gets no second chance.
- **Mitigation**: For `default_make_video`, allow a simple retry (same prompt) after a cooldown, or switch to a minimal custom prompt.

### 6.4 Step 5 → 4B Retry Exhaustion Not Tracked
- **Issue**: If `checkVideoCompletion` returns `video_moderated` or `video_failed`, it goes to Step 4B. But if Step 4B was already attempted once, the workflow doesn't explicitly prevent a second 4B retry.
- **Impact**: Potential infinite loop or double tone-down.
- **Mitigation**: Add a retry counter to the workflow state and enforce `maxRetries = 1` per stage.

---

## 7. State Management & Persistence

### 7.1 No Persistent State Between Runs
- **Issue**: If the browser crashes, the machine reboots, or the process is killed mid-workflow, the tracker record is left in limbo (likely still `pending` or partially updated).
- **Impact**: Duplicate processing, lost records, or manual cleanup required.
- **Mitigation**: Update the tracker to an intermediate status (e.g., `processing`) immediately after Step 1, and use idempotent updates in later steps.

### 7.2 No Cleanup of Input Fields on Failure
- **Issue**: If a step fails after typing a prompt, the input field retains the old text. The next run may append to or be confused by the old text.
- **Impact**: Cross-contamination between records.
- **Mitigation**: Clear the input field (`textContent = ''`) at the start of each prompt entry step.

### 7.3 `extendVideo` Doesn't Return `postUrl`
- **Issue**: Unlike other functions, `extendVideo` returns `{ extendStatus, videoUrl, error }` but not `postUrl`.
- **Impact**: If the extend step is the last step and it fails, the caller may not have a stable `postUrl` for the tracker.
- **Mitigation**: Add `postUrl: window.location.href` to all return paths in `extendVideo`.

---

## 8. Edge Cases in Video/Extend Flow

### 8.1 Video Succeeds but Extend Button Missing
- **Issue**: If Grok removes or renames the "Extend" feature, `extendVideo` fails with `extend_failed`.
- **Impact**: Record marked `partial` even though the video is complete.
- **Mitigation**: Accept `partial` as correct behavior, but add a feature-availability check at the start of Step 6 to skip gracefully.

### 8.2 Extend Prompt Causes Video to Be Re-moderated
- **Issue**: The main video passes moderation, but the extend prompt triggers moderation on the extended portion. The workflow marks it `partial`.
- **Impact**: User gets a non-extended video, which is acceptable, but there's no attempt to generate a shorter extend or fallback.
- **Mitigation**: Document this as expected behavior; no code change needed unless business rules change.

### 8.3 `detectVideoSuccess` — Blob URLs and Non-`.mp4` Sources
- **Issue**: The function checks `video.src.includes('.mp4')` (line 75). If Grok serves videos via blob URLs (`blob:https://...`) or `.webm`, this check fails.
- **Impact**: False negative — video is ready but not detected.
- **Mitigation**: Also check `video.readyState >= 2` (HAVE_CURRENT_DATA) and the presence of `pauseBtn` or `downloadBtn`.

### 8.4 `detectVideoFailure` — Overly Broad Patterns
- **Issue**: The pattern `failed` can match unrelated text on the page (e.g., "Your subscription has **failed** to renew" in a banner).
- **Impact**: False positive — video generation is incorrectly marked as failed.
- **Mitigation**: Scope the text search to specific containers (e.g., `.generation-status`, `.error-message`) instead of the entire `document.body.innerText`.

---

## 9. False Positives in Detection

### 9.1 `detectModeration` Only Checks `eyeOffSvg`
- **Issue**: Moderation may be indicated by text banners ("This content was moderated"), not just the eye-off icon.
- **Impact**: Moderated content may pass undetected.
- **Mitigation**: Add text-based moderation detection in addition to the SVG check.

### 9.2 `isVideoGenerating` — Cancel Button Absent During Extend
- **Issue**: The function checks for the "Cancel Video" button as a generation indicator. If Grok changes the cancel button label or removes it during extension, the script may think generation is complete.
- **Impact**: Premature exit from polling.
- **Mitigation**: Also check for the presence of loading spinners or disabled download buttons.

---

## 10. Operational & Observability Gaps

### 10.1 No Screenshot Capture on Failure
- **Issue**: When a step fails, there is no automatic screenshot saved for post-mortem analysis.
- **Impact**: Debugging requires manual reproduction.
- **Mitigation**: Integrate `browseros_save_screenshot` into every failure path (or at least the first failure per record).

### 10.2 No Telemetry / Metrics
- **Issue**: There is no logging of success rates, average generation time per step, or common failure reasons.
- **Impact**: Cannot identify trends (e.g., "video generation is slower after 6 PM").
- **Mitigation**: Emit structured logs (JSON) with step durations, failure reasons, and retry counts.

### 10.3 Hardcoded `--project 3`
- **Issue**: The workflow is hardcoded for project 3 in all commands.
- **Impact**: Cannot reuse the workflow for other projects without find-replace.
- **Mitigation**: Use a `$PROJECT_ID` variable or make the `--project` argument dynamic.

### 10.4 No Validation of Tracker Response Format
- **Issue**: Step 1 assumes the tracker returns JSON with `id`, `prompt`, `video_prompt`, `extend_prompt`. If the tracker schema changes, the script may crash with `undefined` errors.
- **Impact**: Unhandled exceptions instead of graceful exits.
- **Mitigation**: Validate the tracker response schema before proceeding.

### 10.5 Missing Pre-Flight Browser Check
- **Issue**: The workflow does not verify the browser is responsive or on a valid page before Step 2.
- **Impact**: If a previous run crashed the tab, the navigation may fail silently.
- **Mitigation**: Add a pre-flight check (e.g., `browseros_evaluate_script` with `return navigator.userAgent`) before navigating.

---

## Quick-Win Recommendations (Priority Order)

| Priority | Action | Effort |
|----------|--------|--------|
| **P0** | Add build step to keep `.min.js` in sync with `.js` | Low |
| **P0** | Cache `postUrl` at Step 3 and never overwrite it | Low |
| **P1** | Add CAPTCHA / human-verification detection | Medium |
| **P1** | Scope `detectVideoFailure` to specific DOM containers | Low |
| **P1** | Fix `detectVideoSuccess` to handle blob URLs | Low |
| **P1** | Add retry counter to prevent double 4B retries | Low |
| **P2** | Poll for detail-view readiness instead of fixed 2s wait | Medium |
| **P2** | Add `postUrl` to `extendVideo` return value | Low |
| **P2** | Add fallback selectors for `promptInput` and `submitBtn` | Low |
| **P3** | Add structured JSON telemetry logs | Medium |
| **P3** | Parameterize `--project 3` throughout the workflow | Low |

---

*Generated by systematic review of workflow definition, source JavaScript, and minified artifact.*
