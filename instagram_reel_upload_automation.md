# Instagram Reel Upload Automation Guide

This document outlines a hybrid approach using BrowserOS MCP tools and JavaScript for automating Instagram Reel uploads.

## Overview

Instagram's web interface uses dynamic React components, shadow DOM, and frequent class name changes. A hybrid approach combining MCP tools (for navigation and file uploads) with JavaScript (for element selection) is most reliable.

---

## Prerequisites

```javascript
// File path configuration
const CONFIG = {
  reelFilePath: '/absolute/path/to/your/reel.mp4',  // Must be absolute path
  caption: 'Your caption text here',
  hashtags: '#reels #instagram #automation',
  allowComments: true,
  advancedSettings: false
};
```

---

## Step 1: Navigate to Instagram

**BrowserOS MCP:**
```javascript
// Tool: navigate_page
{
  "page": 64,  // Your active page ID
  "action": "url",
  "url": "https://www.instagram.com/"
}
```

---

## Step 2: Open Create Post Menu

### Method A: Hover over "New Post" button (MCP)

```javascript
// First, take a snapshot to find the element
// Tool: take_snapshot
{
  "page": 64
}

// Hover over the "New post" button
// Tool: hover
{
  "page": 64,
  "element": 47  // Adjust based on snapshot
}
```

### Method B: JavaScript Fallback (More Reliable)

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    // Find the "New post" button by aria-label
    const newPostBtn = document.querySelector('svg[aria-label="New post"]') ||
                      document.querySelector('svg[aria-label="New Post"]');
    
    if (newPostBtn) {
      // Traverse up to find the clickable parent
      let parent = newPostBtn.closest('a') || newPostBtn.closest('button') || newPostBtn.parentElement;
      
      // Trigger hover
      const hoverEvent = new MouseEvent('mouseover', { bubbles: true });
      parent.dispatchEvent(hoverEvent);
      
      return { success: true, element: 'New post button found and hovered' };
    }
    return { success: false, error: 'New post button not found' };
  `
}
```

---

## Step 3: Click Create Button to Open Dropdown

### Method A: MCP

```javascript
// Take snapshot after hover animation
// Tool: take_snapshot

// Click the Create link
// Tool: click
{
  "page": 64,
  "element": 52  // Adjust based on snapshot
}
```

### Method B: JavaScript

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    // Wait for dropdown to appear, then find "Create" option
    const findCreateOption = () => {
      // Multiple selector attempts for resilience
      const selectors = [
        'a:has(span:contains("Create"))',  // CSS :has (limited support)
        'span:contains("Create")',         // jQuery-style
        'div[role="menu"] a',              // Menu item
        'a[href="#"]',                     // Common pattern
        '[role="menuitem"]',               // ARIA role
      ];
      
      // Use XPath for text-based selection
      const xpath = "//span[contains(text(), 'Create')]/ancestor::a | //span[contains(text(), 'Create')]/ancestor::button";
      const result = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
      const createEl = result.singleNodeValue;
      
      if (createEl) {
        createEl.click();
        return { success: true, element: 'Create option clicked' };
      }
      return { success: false, error: 'Create option not found' };
    };
    
    return findCreateOption();
  `
}
```

---

## Step 4: Select "Post" Option (for Reels)

### JavaScript (Recommended)

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    setTimeout(() => {
      // Find the "Post" option in dropdown
      const xpath = "//span[contains(text(), 'Post')]/ancestor::a | //span[contains(text(), 'Post')]/ancestor::button | //div[contains(text(), 'Post')]";
      const result = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
      const postOption = result.singleNodeValue;
      
      if (postOption) {
        postOption.click();
        return { success: true };
      }
      return { success: false };
    }, 500);
  `
}
```

---

## Step 5: Confirm Modal & File Selection

### Wait for Modal (JavaScript)

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    // Poll for modal appearance
    return new Promise((resolve) => {
      let attempts = 0;
      const checkModal = setInterval(() => {
        attempts++;
        const modal = document.querySelector('div[role="dialog"]') ||
                     document.querySelector('div[role="heading"]:contains("Create new post")');
        
        // Check for "Select from computer" button
        const selectBtn = document.querySelector('button') && 
          Array.from(document.querySelectorAll('button')).find(b => 
            b.textContent.includes('Select from computer')
          );
        
        if (selectBtn || attempts > 20) {
          clearInterval(checkModal);
          resolve({ 
            modalFound: !!selectBtn, 
            attempts: attempts,
            buttonText: selectBtn ? selectBtn.textContent : null
          });
        }
      }, 300);
    });
  `
}
```

### Click "Select from computer" (MCP + JavaScript)

```javascript
// Tool: evaluate_script  
{
  "page": 64,
  "expression": `
    const buttons = Array.from(document.querySelectorAll('button'));
    const selectBtn = buttons.find(b => 
      b.textContent.toLowerCase().includes('select from computer')
    );
    
    if (selectBtn) {
      // Store reference for file upload
      window.__instagramFileInput = selectBtn;
      
      // Look for hidden file input or trigger click
      const fileInput = document.querySelector('input[type="file"]') ||
                       selectBtn.querySelector('input[type="file"]');
      
      if (fileInput) {
        window.__instagramFileInput = fileInput;
        return { success: true, inputFound: true };
      }
      
      selectBtn.click();
      return { success: true, clicked: true };
    }
    return { success: false };
  `
}
```

### File Upload (MCP)

```javascript
// Tool: upload_file
{
  "page": 64,
  "element": 58,  // The file input element ID from snapshot
  "files": ["/absolute/path/to/reel.mp4"]
}

// Alternative: If file input is hidden/injected
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    // Create and trigger file input programmatically
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'video/mp4,video/*';
    input.style.display = 'none';
    document.body.appendChild(input);
    
    // Store for MCP upload_file
    input.id = '__mcp_upload_target';
    
    return { inputCreated: true, id: '__mcp_upload_target' };
  `
}
```

---

## Step 6: Video Processing & Crop Selection

### Wait for Upload & Find Crop Button

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    return new Promise((resolve) => {
      let attempts = 0;
      const checkUpload = setInterval(() => {
        attempts++;
        
        // Check for crop button or video preview
        const cropBtn = document.querySelector('svg[aria-label="Select crop"]') ||
                       document.querySelector('svg[aria-label="Crop"]');
        
        const videoPreview = document.querySelector('video');
        
        if (cropBtn || videoPreview || attempts > 30) {
          clearInterval(checkUpload);
          resolve({ 
            cropFound: !!cropBtn, 
            videoFound: !!videoPreview,
            attempts: attempts 
          });
        }
      }, 500);
    });
  `
}
```

### Click Crop & Select Original

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    // Click crop button
    const cropBtn = document.querySelector('svg[aria-label="Select crop"]') ||
                   document.querySelector('svg[aria-label="Crop"]');
    if (cropBtn) {
      (cropBtn.closest('button') || cropBtn.parentElement).click();
      
      setTimeout(() => {
        // Find "Original" option
        const originalBtn = Array.from(document.querySelectorAll('div[role="button"]'))
          .find(el => el.textContent.includes('Original'));
        if (originalBtn) originalBtn.click();
      }, 500);
      
      return { success: true };
    }
    return { success: false };
  `
}
```

---

## Step 7: Proceed to Next Steps

### Click Next (First Time)

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    const findAndClickNext = () => {
      // Look for Next button in header
      const headers = document.querySelectorAll('div[role="dialog"] header, div[role="dialog"] div');
      for (const header of headers) {
        const nextBtn = Array.from(header.querySelectorAll('div[role="button"]'))
          .find(b => b.textContent.trim() === 'Next');
        if (nextBtn) {
          nextBtn.click();
          return { clicked: true, location: 'header' };
        }
      }
      
      // Fallback: any Next button
      const allNext = Array.from(document.querySelectorAll('div[role="button"]'))
        .find(b => b.textContent.trim() === 'Next');
      if (allNext) {
        allNext.click();
        return { clicked: true, location: 'fallback' };
      }
      
      return { clicked: false };
    };
    
    return findAndClickNext();
  `
}
```

### Wait for Filter/Caption Screen & Click Next Again

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    return new Promise((resolve) => {
      setTimeout(() => {
        // Click Next again for final review screen
        const allNext = Array.from(document.querySelectorAll('div[role="button"]'))
          .find(b => b.textContent.trim() === 'Next');
        if (allNext) {
          allNext.click();
          resolve({ clicked: true });
        } else {
          resolve({ clicked: false });
        }
      }, 1500); // Wait for screen transition
    });
  `
}
```

---

## Step 8: Add Caption

### Click Caption Textbox & Type (MCP)

```javascript
// Method A: MCP fill
// First take snapshot to find element
// Tool: take_snapshot

// Tool: fill
{
  "page": 64,
  "element": 73,  // Caption textbox ID
  "text": "Your caption here #reels #automation"
}
```

### Method B: JavaScript (More Control)

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    // Find caption textbox
    const captionBox = document.querySelector('div[role="textbox"][aria-label*="caption"]') ||
                      document.querySelector('div[role="textbox"][placeholder*="caption"]') ||
                      document.querySelector('div[contenteditable="true"]');
    
    if (captionBox) {
      // Focus the element
      captionBox.focus();
      captionBox.click();
      
      // Clear existing content
      captionBox.innerHTML = '';
      
      // Set caption
      const caption = "Your caption here #reels #automation";
      
      // Method 1: Direct HTML (may not trigger React)
      captionBox.innerHTML = caption;
      
      // Method 2: Simulate input events
      captionBox.textContent = caption;
      
      // Trigger React input event
      const inputEvent = new Event('input', { bubbles: true });
      captionBox.dispatchEvent(inputEvent);
      
      const changeEvent = new Event('change', { bubbles: true });
      captionBox.dispatchEvent(changeEvent);
      
      return { success: true, captionSet: captionBox.textContent };
    }
    return { success: false, error: 'Caption box not found' };
  `
}
```

---

## Step 9: Share/Reel Settings (Optional)

### Configure Advanced Settings

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    // Toggle advanced settings if needed
    const advancedToggle = Array.from(document.querySelectorAll('div[role="button"]'))
      .find(b => b.textContent.includes('Advanced settings'));
    
    if (advancedToggle) {
      advancedToggle.click();
      
      setTimeout(() => {
        // Example: Toggle comment settings
        const commentToggle = document.querySelector('[aria-label="Turn off commenting"]') ||
                             document.querySelector('[aria-label="Turn on commenting"]');
        if (commentToggle && !CONFIG.allowComments) {
          commentToggle.click();
        }
      }, 500);
    }
    
    return { advancedSettingsHandled: !!advancedToggle };
  `
}
```

---

## Step 10: Publish

### Click Share Button

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    const shareBtn = Array.from(document.querySelectorAll('div[role="button"]'))
      .find(b => b.textContent.trim() === 'Share');
    
    if (shareBtn) {
      shareBtn.click();
      return { published: true, timestamp: new Date().toISOString() };
    }
    return { published: false, error: 'Share button not found' };
  `
}
```

### Confirm Upload Success

```javascript
// Tool: evaluate_script
{
  "page": 64,
  "expression": `
    return new Promise((resolve) => {
      let attempts = 0;
      const checkSuccess = setInterval(() => {
        attempts++;
        
        // Look for success indicators
        const successIndicators = [
          document.querySelector('svg[aria-label="Your activity"]'),
          document.body.textContent.includes('Your reel has been shared'),
          document.body.textContent.includes('Posted'),
          !document.querySelector('div[role="dialog"]') // Modal closed
        ];
        
        if (successIndicators.some(i => i) || attempts > 20) {
          clearInterval(checkSuccess);
          resolve({ 
            success: successIndicators.some(i => i), 
            attempts: attempts,
            modalClosed: !document.querySelector('div[role="dialog"]')
          });
        }
      }, 1000);
    });
  `
}
```

---

## Complete Automation Script

```javascript
/**
 * Complete Instagram Reel Upload Automation
 * 
 * Usage: Run each step sequentially, waiting for the previous to complete.
 * This script combines BrowserOS MCP tools with JavaScript execution.
 */

const InstagramReelUploader = {
  config: {
    pageId: 64,  // Update with your actual page ID
    reelPath: '/absolute/path/to/reel.mp4',
    caption: 'Check out my latest reel! 🎬',
    hashtags: '#reels #viral #content'
  },

  // Step 1: Navigate
  async navigate() {
    // MCP: navigate_page
    return { action: 'navigate_page', url: 'https://www.instagram.com/' };
  },

  // Step 2: Open create menu
  async openCreateMenu() {
    // JavaScript: evaluate_script
    return {
      expression: `
        const btn = document.querySelector('svg[aria-label="New post"]');
        if (btn) {
          (btn.closest('a') || btn.closest('button')).click();
          return { success: true };
        }
        return { success: false };
      `
    };
  },

  // Step 3: Select Post
  async selectPost() {
    return {
      expression: `
        setTimeout(() => {
          const xpath = "//span[contains(text(), 'Post')]/ancestor::a";
          const el = document.evaluate(xpath, document, null, 
            XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
          if (el) el.click();
        }, 300);
      `
    };
  },

  // Step 4: Upload file (MCP)
  async uploadFile() {
    // First inject file input if needed
    await this.injectFileInput();
    
    // Then use MCP upload_file
    return {
      action: 'upload_file',
      element: '__file_input_id__',  // Get from snapshot
      files: [this.config.reelPath]
    };
  },

  // Step 5: Handle crop and proceed
  async configureAndProceed() {
    return {
      expression: `
        (async () => {
          // Wait for upload
          await new Promise(r => setTimeout(r, 2000));
          
          // Click crop
          const cropSvg = document.querySelector('svg[aria-label="Select crop"]');
          if (cropSvg) cropSvg.closest('button').click();
          
          await new Promise(r => setTimeout(r, 500));
          
          // Select Original
          const original = Array.from(document.querySelectorAll('div[role="button"]'))
            .find(b => b.textContent.includes('Original'));
          if (original) original.click();
          
          await new Promise(r => setTimeout(r, 500));
          
          // Click Next twice
          for (let i = 0; i < 2; i++) {
            await new Promise(r => setTimeout(r, 1000));
            const nextBtn = Array.from(document.querySelectorAll('div[role="button"]'))
              .find(b => b.textContent.trim() === 'Next');
            if (nextBtn) nextBtn.click();
          }
          
          return { completed: true };
        })();
      `
    };
  },

  // Step 6: Add caption
  async addCaption() {
    const fullCaption = this.config.caption + ' ' + this.config.hashtags;
    
    return {
      expression: `
        const captionBox = document.querySelector('div[role="textbox"][aria-label*="caption"]') ||
                          document.querySelector('div[contenteditable="true"]');
        if (captionBox) {
          captionBox.focus();
          captionBox.innerHTML = '${fullCaption.replace(/'/g, "\\'")}';
          captionBox.dispatchEvent(new Event('input', { bubbles: true }));
          return { captionAdded: true };
        }
        return { captionAdded: false };
      `
    };
  },

  // Step 7: Publish
  async publish() {
    return {
      expression: `
        const shareBtn = Array.from(document.querySelectorAll('div[role="button"]'))
          .find(b => b.textContent.trim() === 'Share');
        if (shareBtn) {
          shareBtn.click();
          return { published: true, time: Date.now() };
        }
        return { published: false };
      `
    };
  },

  // Helper: Inject file input
  async injectFileInput() {
    return {
      expression: `
        if (!document.getElementById('__ig_file_input')) {
          const input = document.createElement('input');
          input.type = 'file';
          input.id = '__ig_file_input';
          input.accept = 'video/*';
          input.style.display = 'none';
          document.body.appendChild(input);
        }
        return { inputReady: true };
      `
    };
  }
};

// Export for use
if (typeof module !== 'undefined') module.exports = InstagramReelUploader;
```

---

## Important Notes

### Instagram Anti-Automation Measures

1. **Rate Limiting**: Instagram may block rapid actions. Add delays between steps.
2. **Login State**: Ensure you're already logged in before running automation.
3. **Two-Factor Auth**: If 2FA is enabled, manual intervention may be required.
4. **Element Changes**: Instagram updates selectors frequently. Use multiple fallback selectors.

### Recommended Delays

```javascript
const DELAYS = {
  afterNavigation: 2000,
  afterClick: 500,
  afterFileSelect: 3000,  // Upload takes time
  afterModalOpen: 1000,
  betweenSteps: 1000
};
```

### Debugging Tips

1. **Use `take_screenshot`** at each step to verify state
2. **Check `get_console_logs`** for JavaScript errors
3. **Use `take_enhanced_snapshot`** for complex modals
4. **Log element selectors** to refine automation

### Error Handling

```javascript
const safeExecute = async (stepName, action) => {
  try {
    const result = await action();
    console.log(`✓ ${stepName}:`, result);
    return result;
  } catch (err) {
    console.error(`✗ ${stepName} failed:`, err);
    // Take screenshot for debugging
    await take_screenshot({ page: 64 });
    throw err;
  }
};
```

---

## Selector Reference (Updated as of 2024)

| Element | Primary Selector | Fallback Selectors |
|---------|-----------------|-------------------|
| New Post | `svg[aria-label="New post"]` | `[aria-label*="post"]` |
| Create | `//span[contains(.,"Create")]/ancestor::a` | `div[role="menu"] a:first-child` |
| Post | `//span[contains(.,"Post")]/ancestor::a` | `div[role="menuitem"]:first-child` |
| Select File | `button:contains("Select from computer")` | `input[type="file"]` |
| Crop | `svg[aria-label="Select crop"]` | `svg[aria-label="Crop"]` |
| Original | `div[role="button"]:contains("Original")` | `span:contains("Original")` |
| Next | `div[role="button"]:contains("Next")` | `button:contains("Next")` |
| Caption | `div[role="textbox"][aria-label*="caption"]` | `div[contenteditable="true"]` |
| Share | `div[role="button"]:contains("Share")` | `button:contains("Share")` |

---

## License & Disclaimer

This automation script is for educational purposes. Use in accordance with Instagram's Terms of Service. Automated posting may violate platform policies and could result in account restrictions.
