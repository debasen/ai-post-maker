(async () => {
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));

  const promptText = "Imagine the exact model in a small sailboat mid-sail in a turquoise Caribbean bay. Wearing a striped micro bikini. Head thrown slightly back, laughing into the wind. Full body shot, low angle. The image should be ultra realistic. The image should not be cartoonish or have AI smoothened edges. 9:16 portrait format.";
  const thumbnailId = "89dc566f-5157-4b5d-ae8f-976485aced78";
  const videoPromptText = null;
  const videoType = "spicy";

  async function automateGrokGenerationAdvanced(promptText, thumbnailId, videoPromptText, videoType) {
    const hasVideoPrompt = typeof videoPromptText === 'string' && videoPromptText.trim().length > 0;
    const isSpicy = videoType === 'spicy';

    console.log("🚀 [Grok Automation v4] Starting sequence...");
    console.log(`🎬 Mode: ${hasVideoPrompt ? 'Custom Video Prompt' : isSpicy ? 'Spicy Video' : 'Default Make Video'}`);

    try {
      const postIdMatch = window.location.href.match(/post\/([a-f0-9\-]+)/);

      if (postIdMatch) {
        console.log("📸 Clicking targeted thumbnail...");
        const img = document.querySelector(`img[src*="${thumbnailId}"]`);
        if (img) {
          img.click();
          await wait(2000);
        } else {
          console.warn("⚠️ Thumbnail not found");
        }
      } else {
        console.log("📸 Clicking first image...");
        const imgs = document.querySelectorAll('img');
        if (imgs.length > 0) {
          imgs[0].click();
          await wait(2000);
        }
      }
    } catch (err) {
      console.error("❌ Thumbnail phase error:", err);
    }

    console.log("📝 Finding input box...");
    const editableElement =
      document.querySelector('[placeholder="Type to imagine, @ to reference images"]') ||
      document.querySelector('[data-placeholder="Type to imagine, @ to reference images"]') ||
      document.querySelector('[contenteditable="true"]');

    if (!editableElement) {
      console.error("❌ Input not found");
      return;
    }

    editableElement.click();
    editableElement.focus();
    await wait(500);

    console.log("✍️ Typing prompt...");
    editableElement.textContent = promptText;
    editableElement.dispatchEvent(new Event('input', { bubbles: true }));

    await wait(500);

    console.log("▶️ Submitting...");
    let submitBtn =
      document.querySelector('button[aria-label="Edit"]') ||
      document.querySelector('button[aria-label="Grok"]') ||
      document.querySelector('button[aria-label="Send"]');

    if (!submitBtn) {
      submitBtn = Array.from(document.querySelectorAll('button'))
        .reverse()
        .find(b => b.offsetWidth > 0 && b.offsetHeight > 0);
    }

    if (!submitBtn) {
      console.error("❌ Submit button not found");
      return;
    }

    submitBtn.click();
    console.log("⏳ Waiting for generation...");
    await wait(15000);
    if (!hasVideoPrompt && isSpicy) {
      console.log("🌶️ Looking for 'More options'...");

      let moreOptionsBtn = null;
      for (let i = 0; i < 60; i++) {
        await wait(2000);
        moreOptionsBtn = document.querySelector('button[aria-label="More options"]');
        if (moreOptionsBtn) break;
      }

      if (!moreOptionsBtn) {
        console.error("❌ More options not found");
        return;
      }

      moreOptionsBtn.click();
      await wait(1000);

      console.log("🌶️ Selecting 'Spicy'...");

      let spicyBtn = null;

      try {
        spicyBtn = document.evaluate(
          "//div[@role='menuitem']//div[normalize-space()='Spicy']",
          document,
          null,
          XPathResult.FIRST_ORDERED_NODE_TYPE,
          null
        ).singleNodeValue;
      } catch (e) { }

      if (!spicyBtn) {
        spicyBtn = Array.from(document.querySelectorAll('div[role="menuitem"]'))
          .find(el => el.textContent.includes("Spicy"));
      }

      if (!spicyBtn) {
        console.error("❌ Spicy option not found");
        return;
      }

      const oldUrl = window.location.href;
      spicyBtn.click();

      console.log("⏳ Waiting for video URL...");

      for (let i = 0; i < 15; i++) {
        await wait(2000);
        if (window.location.href !== oldUrl) {
          console.log("✅ Video ready:", window.location.href);
          return;
        }
      }

      console.warn("⚠️ URL didn’t change");
    }
  }

  await automateGrokGenerationAdvanced(promptText, thumbnailId, videoPromptText, videoType);
})();