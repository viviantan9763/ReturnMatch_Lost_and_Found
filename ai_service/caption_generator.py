
import sys
from pathlib import Path

import torch
from PIL import Image
from transformers import BlipProcessor, BlipForConditionalGeneration


MODEL_NAME = "Salesforce/blip-image-captioning-base"


def generate_description(image_path):
    device = "cuda" if torch.cuda.is_available() else "cpu"

    print(f"\nDevice: {device}")
    print(f"Loading BLIP model: {MODEL_NAME}")

    # Load pretrained BLIP processor and model
    processor = BlipProcessor.from_pretrained(MODEL_NAME)
    model = BlipForConditionalGeneration.from_pretrained(
        MODEL_NAME
    ).to(device)

    model.eval()

    # Read image
    image = Image.open(image_path).convert("RGB")

    # Prepare input
    inputs = processor(
        images=image,
        return_tensors="pt"
    ).to(device)

    # Generate caption using BLIP
    with torch.inference_mode():
        output = model.generate(
            **inputs,
            max_new_tokens=40,
            num_beams=3
        )

    description = processor.decode(
        output[0],
        skip_special_tokens=True
    )

    print("\n========== RETURNMATCH BLIP ==========")
    print(f"Image: {image_path}")
    print(f"Generated Description: {description}")
    print("======================================")

    return description


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python caption_generator.py <image_path>")
        sys.exit(1)

    image_path = Path(sys.argv[1])

    if not image_path.is_file():
        print(f"Image not found: {image_path}")
        sys.exit(1)

    generate_description(image_path)
