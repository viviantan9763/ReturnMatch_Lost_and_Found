
import sys
from pathlib import Path

import torch
from PIL import Image
from transformers import CLIPModel, CLIPProcessor


MODEL_NAME = "openai/clip-vit-base-patch32"

# Categories from ReturnMatch's item_category table
CATEGORY_PROMPTS = {
    "Mobile Phone": "a photo of a mobile smartphone",
    "Laptop": "a photo of a laptop computer",
    "Tablet": "a photo of a tablet computer",
    "Wallet": "a photo of a wallet",
    "Jewellery": "a photo of jewellery such as a necklace or ring",
    "Watch": "a photo of a wristwatch",
    "Bag": "a photo of a backpack or handbag",
    "Umbrella": "a photo of an umbrella",
    "Bottle": "a photo of a water bottle",
    "Keys": "a photo of a set of keys",
    "Clothing": "a photo of clothing",
    "Stationery": "a photo of stationery such as pens or pencils",
    "Other": "a photo of a miscellaneous personal item",
}


def classify_image(image_path):
    device = "cuda" if torch.cuda.is_available() else "cpu"

    print(f"\nDevice: {device}")
    print(f"Loading model: {MODEL_NAME}")

    processor = CLIPProcessor.from_pretrained(MODEL_NAME)
    model = CLIPModel.from_pretrained(MODEL_NAME)

    model = model.to(device)
    model.eval()

    image = Image.open(image_path).convert("RGB")

    category_names = list(CATEGORY_PROMPTS.keys())
    prompts = list(CATEGORY_PROMPTS.values())

    inputs = processor(
        text=prompts,
        images=image,
        return_tensors="pt",
        padding=True,
        truncation=True,
    )

    inputs = inputs.to(device)

    with torch.inference_mode():
        outputs = model(**inputs)

        logits = outputs.logits_per_image[0]

        probabilities = torch.softmax(logits, dim=0)

    results = list(
        zip(category_names, probabilities.cpu().tolist())
    )

    results.sort(key=lambda x: x[1], reverse=True)

    print("\n========== RETURNMATCH AI ==========")
    print(f"Image: {image_path}")

    print("\nTop 5 Category Predictions:\n")

    for category, score in results[:5]:
        print(f"{category:<18} {score * 100:.2f}%")

    predicted_category, top_score = results[0]

    print("\n------------------------------------")
    print(f"Suggested Category: {predicted_category}")
    print(f"Relative CLIP Score: {top_score * 100:.2f}%")
    print("------------------------------------")

    print(
        "\nNote: This score is relative to the "
        "provided candidate categories, not a "
        "calibrated probability of correctness."
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python image_classifier.py <image_path>")
        sys.exit(1)

    image_path = Path(sys.argv[1])

    if not image_path.is_file():
        print(f"Image not found: {image_path}")
        sys.exit(1)

    classify_image(image_path)
