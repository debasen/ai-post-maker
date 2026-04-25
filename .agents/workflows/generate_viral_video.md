---
description: Generate a viral short video using IDE-native models
---
# Generate Viral Video Workflow

This workflow guides the AI in generating a complete set of assets for a viral short video, directly within the Antigravity IDE.

## 1. Script Generation
- Use your native LLM capabilities (e.g., Gemini / Google Nano) to generate an engaging, 20-30 second video script based on the user's provided `topic`.
- Outline the script with a clear structure:
  - **Hook** (0-3s): A scroll-stopping opening.
  - **Body** (3-20s): Fast-paced, engaging content.
  - **CTA** (20-25s): A call to action (like/subscribe/comment).
- Present the script to the user in a clear format.

## 2. Visual Assets (Images)
- Based on the script, identify the visual aesthetic and character needed for the video (e.g., a cooking chef, a fitness coach, etc.).
- Use your built-in `generate_image` tool to create 1-2 ultra-realistic, cinematic, vertical (9:16) portrait images of the main subject.
- Use highly descriptive prompts focusing on natural lighting, realistic textures, and expressive faces.

## 3. Video Synthesis (Agentic models)
- Utilize the IDE's native video engine models (e.g., Google Video/Vision models, Gemini Nano capabilities) to animate the generated static image and sync it with a synthesized voiceover of the script.
- *Fallback: If direct video/audio synthesis tools are not currently exposed in your toolset, you must simulate the workflow by providing the finished script and the finalized 9:16 portrait images to the user. Explain to the user how they can use these assets in external tools (like CapCut, Premiere, or HeyGen) to fuse them into the final video.*

## 4. Final Review
- Present all the generated assets (the Script, the `.webp` Image artifacts from `generate_image`, and the Video if generated) to the user.
- Ask for their feedback and if they want any specific asset tweaked or regenerated.
