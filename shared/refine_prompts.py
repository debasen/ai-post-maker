"""
refine_prompts.py
Applies prompt and caption refinements to grok_prompts_{N}.json.

Usage:
    python3 shared/refine_prompts.py --project <1|2>
"""
import json
import os
import sys
import argparse

PROMPT_REPLACEMENTS_P1 = {
    "vibrant": "neon-drenched",
    "playful glance": "piercing, seductive stare",
    "soft smile": "sultry look",
    "playfully": "sultrily",
    "joyful": "mischievous",
    "softly": "sultrily",
    "dreamily": "seductively",
    "cool, confident stare": "fierce, confident stare",
    "Smiling warmly": "Smiling mischievously",
    "adventurous expression": "sultry, adventurous expression",
    "joyful expression": "sultry, high-energy expression",
    "thoughtfully": "seductively",
    "energetic posture": "fierce, energetic posture",
    "looking curiously": "looking seductively",
    "laughing joyfully": "laughing mischievously",
    "serene expression": "sultry, serene expression",
    "leaning casually": "leaning provocatively",
    "soft breeze": "warm breeze",
    "soft, dramatic lighting": "moody, dramatic lighting",
    "playful smile": "sultry, playful smile",
    "smiling sweetly": "smiling mischievously",
    "calm and ethereal": "sultry and ethereal",
}

CAPTION_HASHTAGS_P1 = (
    " #baddie #modelvibe #sultry #realisticai #fashionmodel "
    "#hotgirl #stunning #fitgirl #portraitmodel #edgyfashion"
)

def refine_prompt_p1(prompt: str) -> str:
    prompt = prompt.replace(" 9:16 portrait format.", "")
    if not prompt.startswith("Imagine the exact model"):
        prompt = "Imagine the exact model in a " + prompt[0].lower() + prompt[1:]
    realism_clause = " The image should be ultra realistic. The image should not be cartoonish or have AI smoothened edges. 9:16 portrait format."
    if realism_clause not in prompt:
        prompt += realism_clause
    for old, new in PROMPT_REPLACEMENTS_P1.items():
        prompt = prompt.replace(old, new)
    return prompt

def refine_caption_p1(caption: str) -> str:
    parts = caption.split("#")
    base_caption = parts[0].strip()
    if "Basking" in base_caption:
        base_caption = base_caption.replace("Basking", "Owning")
    return f"{base_caption} 🔥😈{CAPTION_HASHTAGS_P1}"

def main():
    parser = argparse.ArgumentParser(description="Refine prompts and captions.")
    parser.add_argument("--project", required=True, choices=["1", "2"])
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    file_path = os.path.join(repo_root, f"grok_prompts_{args.project}.json")

    if args.project == "2":
        print(f"Project 2 uses shared/make_edgy.py for custom sassy refinement.")
        return

    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found")
        sys.exit(1)

    with open(file_path, "r") as f:
        data = json.load(f)

    for item in data["prompts"]:
        item["prompt"] = refine_prompt_p1(item["prompt"])
        item["instagram_caption"] = refine_caption_p1(item["instagram_caption"])

    with open(file_path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"Refined {len(data['prompts'])} prompts in {file_path}")

if __name__ == "__main__":
    main()
