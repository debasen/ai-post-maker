---
description: End-to-end automation skill for generating videos on Grok from pending prompts using Python scripts for tracking.
---

### Step 1: Pick the Next Pending Prompt
1. Run the following command to get the next pending prompt:
   ```bash
   python3 scripts/grok_tracker.py get_next
   ```
2. Get the `id`, `prompt`, and `instagram_caption` from the output.

### Step 2: Ensure Browser Context
- Ensure you have a browser window active on Grok: https://grok.com/imagine/post/89dc566f-5157-4b5d-ae8f-976485aced78
- If not already on the correct interface, navigate there using the `navigate_page` tool from the browseros MCP.

### Step 3: Execute Unified Automation Script
Inject and evaluate the following asynchronous JavaScript snippet into the active Grok tab using the `evaluate_script` tool from the browseros MCP. Pass the `prompt` string into the script.

```javascript
/**
 * Executes the complete Grok Image-to-Video DOM automation sequence.
 * @param {string} promptText The prompt to insert into the generation box.
 * @returns {Promise<Object>} An object containing { success, videoUrl, postUrl, error }
 */
async function automateGrokGeneration(promptText) {
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  console.log("🚀 [Grok Automation] Starting sequence...");

  // 1. Attempt to find and click an image thumbnail if we are on a post page
  try {
    const postIdMatch = window.location.href.match(/post\/([a-f0-9\-]+)/);
    if (postIdMatch) {
      console.log("📸 [Grok Automation] Detected post URL, attempting to click targeted thumbnail...");
      const postId = postIdMatch[1];
      const img = document.querySelector(`img[src*="89dc566f-5157-4b5d-ae8f-976485aced78"]`);
      if (img) {
        img.click();
      await wait(2000); 
      } else {
        console.warn(`⚠️ [Grok Automation] Thumbnail with ID ${postId} not found.`);
      }
    } else {
      console.log("📸 [Grok Automation] Not on a specific post. Clicking first available image if present.");
      const imgs = document.querySelectorAll('img');
      if (imgs.length > 0) {
        imgs[0].click();
        await wait(2000);
      }
    }
  } catch (err) {
    console.error("❌ [Grok Automation] Error in step 1 (thumbnail click):", err);
  }

  // 2. Select the editable paragraph
  console.log("📝 [Grok Automation] Locating prompt input box...");
  const editableElement = document.querySelector('[placeholder="Describe your edit, @ to reference images"]') ||
                          document.querySelector('[data-placeholder="Describe your edit, @ to reference images"]') ||
                          document.querySelector('[contenteditable="true"]');
                          
  if (!editableElement) {
    console.error("❌ [Grok Automation] Prompt input box not found!");
    return { error: "Prompt input box not found. Make sure you are on a valid image edit view or chat." };
  }
  
  editableElement.click();
  editableElement.focus();
  await wait(500);

  // 3. Inject the prompt text dynamically
  console.log("✍️ [Grok Automation] Injecting prompt text...");
  editableElement.textContent = promptText;
  editableElement.dispatchEvent(new Event('input', { bubbles: true }));
  editableElement.dispatchEvent(new Event('change', { bubbles: true }));
  await wait(500);

  // 4. Click Submit
  console.log("▶️ [Grok Automation] Attempting to click Submit...");
  let submitBtn = document.querySelector('button[aria-label="Edit"]') || 
                  document.querySelector('button[aria-label="Grok"]') || 
                  document.querySelector('button[aria-label="Send"]');

  if (!submitBtn) {
    // generic fallback: last visible button near the text box
    const buttons = Array.from(document.querySelectorAll('button'));
    submitBtn = buttons.reverse().find(b => {
      const rect = b.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    });
  }

  if (!submitBtn) {
    console.error("❌ [Grok Automation] Submit button not found!");
    return { error: "Submit button not found." };
  }
  
  submitBtn.click();
  console.log("⏳ [Grok Automation] Prompt submitted. Polling for 'Make video' button...");

  // 5. Poll for the generated image and its 'Make video' button
  let makeVideoBtn = null;
  for (let i = 0; i < 60; i++) { // wait up to 120s
    await wait(2000);
    const buttons = Array.from(document.querySelectorAll('button'));
    makeVideoBtn = buttons.find(btn => 
      (btn.textContent && btn.textContent.includes('Make video')) || 
      btn.getAttribute('aria-label') === 'Make video'
    );
    
    if (makeVideoBtn) {
      console.log("✅ [Grok Automation] 'Make video' button found!");
      break;
    }
    if (i % 5 === 0) console.log(`⏳ [Grok Automation] Polling... attempt ${i+1}/60`);
  }

  if (!makeVideoBtn) {
    console.error("❌ [Grok Automation] 'Make video' button did not appear.");
    return { error: "'Make video' button did not appear. Generation may have timed out or failed." };
  }

  const postUrl = window.location.href; // The image post URL

  // 6. Click 'Make video'
  console.log("🎥 [Grok Automation] Clicking 'Make video'...");
  const oldUrl = window.location.href;
  makeVideoBtn.click();
  console.log("⏳ [Grok Automation] Waiting for URL propagation to video job...");

  // 7. Await the final URL redirect (Target Video Job URL)
  for (let i = 0; i < 15; i++) { // Poll for up to 30s
    await wait(2000);
    if (window.location.href !== oldUrl) {
      console.log(`✅ [Grok Automation] Success! Video URL: ${window.location.href}`);
      return { success: true, videoUrl: window.location.href, postUrl: postUrl };
    }
  }

  console.warn("⚠️ [Grok Automation] URL did not change after clicking 'Make video'. Assumed started.");
  return { 
    success: true, 
    videoUrl: window.location.href, 
    postUrl: postUrl,
    warning: "URL did not change, but 'Make video' workflow concluded." 
  };
}
// Usage: return await automateGrokGeneration("PROMPT_TEXT_HERE");
```

### Step 4: Update the Tracker
Once the script successfully executes and returns `{ success: true, videoUrl: "...", postUrl: "..." }`:
1. Run the update command using the `id` from Step 1:
   ```bash
   python3 scripts/grok_tracker.py complete <ID> "<VIDEO_URL>" "<POST_URL>"
   ```
2. Verify the script returns a success JSON.