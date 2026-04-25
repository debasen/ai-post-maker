# Grok Image Edit + Video Workflow

## Tested and Working Steps

### Step 1: Check for existing Grok tab or navigate
Check if there is already an available browser tab open for Grok (e.g., `https://grok.com/imagine/...`).
- If a tab is available, use that tab and skip to Step 2.
- Otherwise, navigate to the Grok image post page:
```python
navigate_page(pageID, "url", "https://grok.com/imagine/post/2d750d9f-4be1-4ee5-a4be-f28552077a52")
```

### Step 2: Navigate to the first thumbnail image
After Step 1 is finished, use the following JS selector to find and click on the first image tile:
```javascript
(function() {
  const img = document.querySelector('img[src="https://imagine-public.x.ai/imagine-public/share-images/2d750d9f-4be1-4ee5-a4be-f28552077a52.jpg"]');
  if (img) img.click();
})()
```
Wait for this to load. This confirms you're on the correct image page.

### Step 3: Click the editable paragraph (CRITICAL)
**This is required before entering the prompt!**
Try to find and click using:
```javascript
(function() {
  const editableElement = document.querySelector('[placeholder="Describe your edit, @ to reference images"]') ||
                          document.querySelector('[data-placeholder="Describe your edit, @ to reference images"]') ||
                          document.querySelector('[contenteditable="true"]');
  if (editableElement) {
    editableElement.click();
    // In some cases we might need to focus it too
    editableElement.focus();
  }
})()
```
- Without this click, the workflow won't work

### Step 4: Find and enter the prompt via JavaScript

**Prompt Guidelines:**
Write a short prompt that includes:
- Scene description
- Outfit details (Prefer short outfits but avoid)
- Pose details
- Camera angle and zoom
- Output format (9:16 portrait)

Note: The prompt box already includes a reference image of the model.

**Example Prompt (Don't use the same):**
"Full body shot of the model in a vibrant rooftop lounge at night. Wearing a short black leather skirt and a neon-lit cropped top. Leaning against the glass railing with a playful glance. Medium wide shot, high angle. 9:16 portrait format."

```javascript
(function() {
  const editableP = document.querySelector('[data-placeholder="Describe your edit, @ to reference images"]');
  if (!editableP) return "Element not found";
  
  // Focus and click
  editableP.focus();
  editableP.click();
  
  // Set the prompt text
  const prompt = <YOUR PROMPT HERE>;
  
  // Use textContent for better compatibility
  editableP.textContent = prompt;
  
  // Trigger input events
  editableP.dispatchEvent(new Event('input', { bubbles: true }));
  editableP.dispatchEvent(new Event('change', { bubbles: true }));
  
  return "Prompt entered: " + prompt;
})()
```

### Step 5: Click the submit button (using JavaScript approach)
```javascript
(function() {
  // Find the submit button by its type and aria-label
  const submitBtn = document.querySelector('button[type="button"][aria-label="Edit"]');
  if (submitBtn) {
    submitBtn.click();
    return "Clicked submit button";
  }
  return "No button found";
})()
```

### Step 6: Wait for image generation
- Wait ~15-20 seconds for the 2 new images to generate
- You can monitor progress:
  - Status shows "Generating 0%" initially
  - 1-2 New thumbnails appear

### Step 7: Click the "Make video" button on one of the new images
Use a text-based JavaScript selector to find and click the button:
```javascript
(function() {
  const buttons = Array.from(document.querySelectorAll('button'));
  const makeVideoBtn = buttons.find(btn => 
    btn.textContent.includes('Make video') || 
    btn.getAttribute('aria-label') === 'Make video'
  );
  
  if (makeVideoBtn) {
    makeVideoBtn.click();
    return "Clicked Make video button";
  }
  return "Make video button not found";
})()
```
- After clicking, status shows "Generating x%..."
- You do NOT need to wait for the video generation to complete.
- Once it moves to the generation thumbnail, the new video URL is immediately available in the browser's address bar. Extract it and proceed to the next step.

### Step 8: Create an Instagram-Ready Caption
Prepare a catchy, engaging caption with hashtags for Instagram based on the generated prompt and context.

### Step 9: Log to Tracker
Document the completed generation details in `grok_generations.md` at the end of the process to maintain a tracking record. Ensure you capture the used prompt, post URL, generated video URL, and the created Instagram caption.
