/**
 * Grok Video Asset Downloader Helper (v1)
 *
 * Usage: Inject via evaluate_script, then call helper functions.
 * This script detects video presence and extracts metadata from Grok post pages.
 */

const GrokDownloader = {
  /**
   * Check if the current page has a downloadable video.
   * Returns { hasVideo, videoSrc, hasDownloadBtn, downloadBtnEnabled, postId }
   */
  checkPage() {
    const video = document.querySelector('video');
    const downloadBtn = document.querySelector('button[aria-label="Download"]');
    const postIdMatch = window.location.href.match(/post\/([a-f0-9\-]+)/);

    return {
      hasVideo: !!video,
      videoSrc: video ? (video.currentSrc || video.src) : null,
      hasDownloadBtn: !!downloadBtn,
      downloadBtnEnabled: downloadBtn ? !downloadBtn.disabled : false,
      postId: postIdMatch ? postIdMatch[1] : null,
      url: window.location.href,
    };
  },

  /**
   * Wait for a video element to appear on the page.
   * Useful after navigation when the video hasn't loaded yet.
   * Returns the checkPage() result.
   */
  async waitForVideo(maxAttempts = 30, intervalMs = 1000) {
    for (let i = 0; i < maxAttempts; i++) {
      const state = this.checkPage();
      if (state.hasVideo && state.videoSrc) {
        console.log(`[GrokDownloader] Video found after ${i + 1} attempts.`);
        return state;
      }
      if (i % 5 === 0) {
        console.log(`[GrokDownloader] Waiting for video... attempt ${i + 1}/${maxAttempts}`);
      }
      await new Promise((r) => setTimeout(r, intervalMs));
    }
    console.warn('[GrokDownloader] Video not found within timeout.');
    return this.checkPage();
  },

  /**
   * Find the Download button element and return its bounding rect.
   * Useful for coordinate-based clicking if snapshot IDs aren't available.
   */
  findDownloadButton() {
    const btn = document.querySelector('button[aria-label="Download"]');
    if (!btn) return null;
    const rect = btn.getBoundingClientRect();
    return {
      found: true,
      x: rect.left + rect.width / 2,
      y: rect.top + rect.height / 2,
      width: rect.width,
      height: rect.height,
      disabled: btn.disabled,
    };
  },

  /**
   * Programmatically trigger a download by fetching the video blob
   * and creating a temporary anchor. Note: this downloads to the
   * browser's default download folder with a generic name.
   * Prefer MCP download_file for controlled save paths.
   */
  async triggerBrowserDownload(filename = 'grok-video.mp4') {
    const state = this.checkPage();
    if (!state.videoSrc) {
      throw new Error('No video source found on page.');
    }

    console.log(`[GrokDownloader] Fetching video from ${state.videoSrc}...`);
    const response = await fetch(state.videoSrc, { credentials: 'include' });
    if (!response.ok) {
      throw new Error(`Fetch failed: ${response.status} ${response.statusText}`);
    }

    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    console.log(`[GrokDownloader] Browser download triggered for ${filename}`);
    return { success: true, size: blob.size };
  },

  /**
   * Navigate to a given URL and wait for load.
   * NOTE: This will unload the current page and kill any running scripts.
   * Only use this if you are calling it as the final action.
   */
  navigateTo(url) {
    window.location.href = url;
    return { navigated: true, target: url };
  },
};

// Make available globally for evaluate_script access
window.GrokDownloader = GrokDownloader;

// Also export for module environments
if (typeof module !== 'undefined' && module.exports) {
  module.exports = GrokDownloader;
}
