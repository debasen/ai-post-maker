/**
 * Instagram Reel Upload Automation Script
 *
 * Exported functions (for evaluate_script prepend pattern):
 *   openCreateModal()       → { success, error? }
 *   exposeFileInputs()      → { exposed }
 *   advanceToCaption()      → { success, cropFound, originalFound, modalLabelAfter, error?, step? }
 *   enterCaption(text)      → { success, captionEntered?, shareBtnFound?, modalLabel?, error? }
 *   clickShare()            → { success, error? }
 */

// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const xpathOne = (expr) =>
  document.evaluate(expr, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;

// ─────────────────────────────────────────────────────────────
// STEP 1: Open Create Modal + Select "Post"
// ─────────────────────────────────────────────────────────────
async function openCreateModal() {
  // 1. Click "New post" (Create) sidebar item via XPath
  let createBtn =
    xpathOne("//svg[@aria-label='New post']/ancestor::a") ||
    xpathOne("//a[.//span[contains(text(),'Create')]]") ||
    document.querySelector('svg[aria-label="New post"]')?.closest('a');

  if (createBtn) {
    createBtn.click();
    await wait(2000);
  } else {
    return { success: false, error: 'Create button not found' };
  }

  // 2. Click "Post" option from the dropdown
  let postBtn =
    xpathOne("//span[contains(text(),'Post')]/ancestor::a") ||
    xpathOne("//span[contains(text(),'Post')]/ancestor::div[@role='button']") ||
    Array.from(document.querySelectorAll('[role="menuitem"], a'))
      .find((el) => el.textContent.trim() === 'Post');

  if (postBtn) {
    postBtn.click();
    await wait(2000);
  } else {
    return { success: false, error: 'Post menu item not found' };
  }

  return { success: true };
}

// ─────────────────────────────────────────────────────────────
// STEP 2: Expose Hidden File Inputs
// ─────────────────────────────────────────────────────────────
function exposeFileInputs() {
  const fileInputs = document.querySelectorAll('input[type="file"]');
  Array.from(fileInputs).forEach((fi, i) => {
    fi.style.cssText = `display:block!important;visibility:visible!important;opacity:1!important;position:fixed!important;top:${10 + i * 50}px!important;left:10px!important;z-index:99999!important;width:150px!important;height:40px!important;`;
    fi.id = `ig_file_input_${i}`;
  });
  return { exposed: fileInputs.length };
}

// ─────────────────────────────────────────────────────────────
// STEP 3: Crop → Filter/Edit → Caption screen navigation
// NOTE: Split into TWO calls to avoid CDP timeout (>15s total await)
// ─────────────────────────────────────────────────────────────
async function advanceToCaption() {
  // Wait for React to process the file upload
  await wait(4000);

  const modalLabel = document.querySelector('div[role="dialog"]')?.getAttribute('aria-label');

  // 1. Select crop option
  const cropSvg =
    document.querySelector('svg[aria-label="Select crop"]') ||
    document.querySelector('svg[aria-label="Crop"]');
  const cropBtn = cropSvg ? (cropSvg.closest('button') || cropSvg.parentElement) : null;
  if (cropBtn) { cropBtn.click(); await wait(1000); }

  // 2. Select "Original" aspect ratio
  const originalBtn =
    xpathOne("//div[@role='button'][.//span[contains(text(),'Original')]]") ||
    xpathOne("//div[@role='button'][contains(text(),'Original')]") ||
    Array.from(document.querySelectorAll('div[role="button"]'))
      .find((el) => el.textContent.trim().includes('Original'));
  if (originalBtn) { originalBtn.click(); await wait(1000); }

  // 3. Click Next (crop → filter/edit screen)
  let nextBtn =
    xpathOne("//div[@role='button'][normalize-space(text())='Next']") ||
    Array.from(document.querySelectorAll('div[role="button"]'))
      .find((el) => el.textContent.trim() === 'Next');
  if (nextBtn) { nextBtn.click(); await wait(3000); }
  else return { success: false, step: 'Next-1', modalLabel, cropFound: !!cropBtn, originalFound: !!originalBtn };

  // 4. Click Next again (filter/edit → caption screen)
  nextBtn =
    xpathOne("//div[@role='button'][normalize-space(text())='Next']") ||
    Array.from(document.querySelectorAll('div[role="button"]'))
      .find((el) => el.textContent.trim() === 'Next');
  if (nextBtn) { nextBtn.click(); await wait(3000); }
  else return { success: false, step: 'Next-2' };

  return {
    success: true,
    modalLabelAfter: document.querySelector('div[role="dialog"]')?.getAttribute('aria-label'),
    cropFound: !!cropBtn,
    originalFound: !!originalBtn,
  };
}

// ─────────────────────────────────────────────────────────────
// STEP 4: Enter Caption
// ─────────────────────────────────────────────────────────────
async function enterCaption(captionText) {
  const editableBox =
    xpathOne("//div[@role='textbox'][contains(@aria-label,'caption')]") ||
    document.querySelector('div[role="textbox"][aria-label="Write a caption..."]') ||
    document.querySelector('div[contenteditable="true"]');

  if (!editableBox) {
    return {
      success: false,
      step: 'caption',
      error: 'Caption box not found',
      allTextboxLabels: Array.from(document.querySelectorAll('[role="textbox"]'))
        .map((el) => el.getAttribute('aria-label')),
    };
  }

  editableBox.focus();
  editableBox.click();
  document.execCommand('insertText', false, captionText);
  editableBox.dispatchEvent(new Event('input', { bubbles: true }));
  await wait(1000);

  // Locate Share button — verify presence but DO NOT click yet
  const shareBtn =
    xpathOne("//div[@role='button'][normalize-space(text())='Share']") ||
    Array.from(document.querySelectorAll('div[role="button"]'))
      .find((el) => el.textContent.trim() === 'Share');

  return {
    success: true,
    captionEntered: editableBox.textContent.substring(0, 120),
    shareBtnFound: !!shareBtn,
    modalLabel: document.querySelector('div[role="dialog"]')?.getAttribute('aria-label'),
  };
}

// ─────────────────────────────────────────────────────────────
// STEP 5: Click Share
// ─────────────────────────────────────────────────────────────
async function clickShare() {
  const shareBtn =
    xpathOne("//div[@role='button'][normalize-space(text())='Share']") ||
    Array.from(document.querySelectorAll('div[role="button"]'))
      .find((el) => el.textContent.trim() === 'Share');

  if (!shareBtn) {
    return { success: false, error: 'Share button not found' };
  }

  shareBtn.click();
  await wait(3000);

  return { success: true };
}

// Export for module environments
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    openCreateModal,
    exposeFileInputs,
    advanceToCaption,
    enterCaption,
    clickShare,
  };
}
