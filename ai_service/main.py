"""ReturnMatch AI Service: classification, captions, embeddings, and hybrid matching.

Run: python -m uvicorn main:app --host 127.0.0.1 --port 8001
The hybrid endpoint is a prototype; it does NOT approve claims or send notifications.
"""

from contextlib import asynccontextmanager
from io import BytesIO
import re
import unicodedata

from pydantic import BaseModel
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

import torch
import torch.nn.functional as F
from PIL import Image, ImageOps, UnidentifiedImageError
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from transformers import (
    CLIPModel,
    CLIPProcessor,
    BlipProcessor,
    BlipForConditionalGeneration,
)

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
CLIP_MODEL_NAME = "openai/clip-vit-base-patch32"
BLIP_MODEL_NAME = "Salesforce/blip-image-captioning-base"
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB per image
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}

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

# Initial heuristic weights; NOT empirically calibrated.
HYBRID_WEIGHTS = {
    "image": 0.45,
    "text": 0.25,
    "model": 0.20,
    "colour": 0.10,
}

UNKNOWN_VALUES = {
    "", "unknown", "not sure", "unsure", "n a", "na", "none",
    "not applicable", "dont know", "do not know", "no idea", "unspecified",
}
GENERIC_MODELS = {
    "iphone", "apple iphone", "phone", "mobile phone", "smartphone",
    "samsung", "galaxy", "samsung galaxy", "pixel", "google pixel",
    "laptop", "computer", "tablet", "watch", "bag", "bottle",
    "macbook", "macbook pro", "macbook air", "other",
}

models = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"Starting ReturnMatch AI on {DEVICE}")
    print("Loading CLIP...")
    models["clip_processor"] = CLIPProcessor.from_pretrained(
        CLIP_MODEL_NAME, use_fast=False,
    )
    models["clip"] = CLIPModel.from_pretrained(
        CLIP_MODEL_NAME,
    ).to(DEVICE).eval()

    print("Loading BLIP...")
    models["blip_processor"] = BlipProcessor.from_pretrained(
        BLIP_MODEL_NAME, use_fast=False,
    )
    models["blip"] = BlipForConditionalGeneration.from_pretrained(
        BLIP_MODEL_NAME,
    ).to(DEVICE).eval()
    print("ReturnMatch AI models ready!")
    yield
    models.clear()
    if DEVICE == "cuda":
        torch.cuda.empty_cache()


app = FastAPI(
    title="ReturnMatch AI Service", version="1.2.0", lifespan=lifespan,
)


def load_uploaded_image(file: UploadFile) -> Image.Image:
    """Validate image and return EXIF-corrected RGB PIL image."""
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail="Only JPEG, PNG and WEBP images are supported",
        )
    contents = file.file.read(MAX_FILE_SIZE + 1)
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=413, detail="Image must not exceed 10 MB",
        )
    if not contents:
        raise HTTPException(status_code=400, detail="Image file is empty")
    try:
        with Image.open(BytesIO(contents)) as original_image:
            original_image.load()
            return ImageOps.exif_transpose(original_image).convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(status_code=400, detail="Invalid image file")


def get_normalized_clip_embedding(image: Image.Image) -> torch.Tensor:
    """Return unit-length CLIP projected image embedding on CPU."""
    clip_processor = models["clip_processor"]
    clip_model = models["clip"]
    image_inputs = clip_processor(
        images=image, return_tensors="pt",
    ).to(DEVICE)
    with torch.inference_mode():
        vision_outputs = clip_model.vision_model(
            pixel_values=image_inputs["pixel_values"],
        )
        image_features = clip_model.visual_projection(
            vision_outputs.pooler_output,
        )
        normalized_features = F.normalize(
            image_features.float(), p=2, dim=-1,
        )
    return normalized_features[0].cpu()


def generate_blip_caption(image: Image.Image) -> str:
    """Generate a caption; use stored captions later to avoid repeat inference."""
    blip_processor = models["blip_processor"]
    blip_model = models["blip"]
    blip_inputs = blip_processor(
        images=image, return_tensors="pt",
    ).to(DEVICE)
    with torch.inference_mode():
        generated_ids = blip_model.generate(
            **blip_inputs, max_new_tokens=40, num_beams=3,
        )
    return blip_processor.decode(
        generated_ids[0], skip_special_tokens=True,
    ).strip()


@app.get("/health")
def health():
    return {
        "status": "ready",
        "device": DEVICE,
        "clip_model": CLIP_MODEL_NAME,
        "blip_model": BLIP_MODEL_NAME,
    }


# Existing endpoint: keep response keys unchanged for Flutter.
@app.post("/analyze-image")
def analyze_image(file: UploadFile = File(...)):
    image = load_uploaded_image(file)

    clip_processor = models["clip_processor"]
    clip_model = models["clip"]
    categories = list(CATEGORY_PROMPTS.keys())
    prompts = list(CATEGORY_PROMPTS.values())

    clip_inputs = clip_processor(
        text=prompts,
        images=image,
        return_tensors="pt",
        padding=True,
        truncation=True,
    ).to(DEVICE)
    with torch.inference_mode():
        clip_outputs = clip_model(**clip_inputs)
        probabilities = torch.softmax(
            clip_outputs.logits_per_image[0], dim=0,
        )

    predictions = [
        {
            "category": category,
            "score_percent": round(float(score) * 100, 2),
        }
        for category, score in zip(
            categories, probabilities.cpu().tolist(),
        )
    ]
    predictions.sort(
        key=lambda item: item["score_percent"], reverse=True,
    )

    description = generate_blip_caption(image)

    return {
        "success": True,
        "suggested_category": predictions[0]["category"],
        "relative_score_percent": predictions[0]["score_percent"],
        "top_predictions": predictions[:5],
        "generated_description": description,
        "device": DEVICE,
    }


@app.post("/embed-image")
def embed_image(file: UploadFile = File(...)):
    image = load_uploaded_image(file)
    embedding = get_normalized_clip_embedding(image)
    return {
        "success": True,
        "model": CLIP_MODEL_NAME,
        "embedding_dimension": int(embedding.numel()),
        "normalized": True,
        "embedding": embedding.tolist(),
    }


@app.post("/compare-images")
def compare_images(
    lost_image: UploadFile = File(...),
    found_image: UploadFile = File(...),
):
    lost = load_uploaded_image(lost_image)
    found = load_uploaded_image(found_image)
    lost_embedding = get_normalized_clip_embedding(lost)
    found_embedding = get_normalized_clip_embedding(found)

    # Unit-length embeddings: dot product equals cosine similarity.
    image_cosine = float(torch.dot(lost_embedding, found_embedding).item())
    image_cosine = max(-1.0, min(1.0, image_cosine))
    return {
        "success": True,
        "model": CLIP_MODEL_NAME,
        "image_similarity_score": round(image_cosine, 4),
        "image_similarity_percent": round(image_cosine * 100, 2),
        "note": (
            "Cosine similarity is a visual feature score, not a calibrated "
            "probability of a true Lost-Found match or proof of ownership."
        ),
    }


# ---------- TF-IDF Text Similarity ----------

class TextComparisonRequest(BaseModel):
    lost_text: str = ""
    found_text: str = ""


def tfidf_pair_score(left: str, right: str) -> float | None:
    """Pairwise prototype; use corpus-fitted TF-IDF for production ranking."""
    if not left.strip() or not right.strip():
        return None
    vectorizer = TfidfVectorizer(
        lowercase=True,
        strip_accents="unicode",
        ngram_range=(1, 2),
    )
    try:
        matrix = vectorizer.fit_transform([left.strip(), right.strip()])
    except ValueError:
        return None
    value = float(cosine_similarity(matrix[0:1], matrix[1:2])[0][0])
    return max(0.0, min(1.0, value))


@app.post("/compare-text")
def compare_text(request: TextComparisonRequest):
    score = tfidf_pair_score(request.lost_text, request.found_text)
    if score is None:
        return {
            "success": True,
            "text_similarity_score": None,
            "text_similarity_percent": None,
            "status": "insufficient_text",
        }
    return {
        "success": True,
        "algorithm": "TF-IDF + Cosine Similarity",
        "text_similarity_score": round(score, 4),
        "text_similarity_percent": round(score * 100, 2),
        "status": "compared",
    }


# ---------- Phase 2: Hybrid Lost-Found Matching ----------

def clean_words(value: str) -> str:
    """Lowercase, remove accents and punctuation, collapse whitespace."""
    value = unicodedata.normalize("NFKD", value or "")
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = value.casefold().replace("’", "'")
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", value)).strip()


def is_unknown(value: str) -> bool:
    return clean_words(value) in UNKNOWN_VALUES


def normalize_category(value: str) -> str | None:
    text = clean_words(value)
    if text in UNKNOWN_VALUES or text == "other":
        return None
    aliases = {
        "phone": "mobile phone",
        "smartphone": "mobile phone",
        "mobile": "mobile phone",
        "jewelry": "jewellery",
        "key": "keys",
        "backpack": "bag",
        "handbag": "bag",
        "water bottle": "bottle",
    }
    return aliases.get(text, text)


def normalize_model(value: str) -> str | None:
    text = clean_words(value)
    if text in UNKNOWN_VALUES:
        return None
    # Remove only manufacturer prefixes that are redundant for these families.
    for prefix in ("apple iphone ", "samsung galaxy ", "google pixel "):
        if text.startswith(prefix):
            text = text.split(" ", 1)[1]
            break
    text = re.sub(r"(?<=[a-z])(?=\d)|(?<=\d)(?=[a-z])", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if text in GENERIC_MODELS or not text:
        return None
    return text


def model_pair_score(lost: str, found: str) -> float | None:
    a = normalize_model(lost)
    b = normalize_model(found)
    if a is None or b is None:
        return None
    # Conservative exact normalized model comparison: 15 Pro != 15 Pro Max.
    return 1.0 if a == b else 0.0


def normalize_colours(value: str) -> set[str] | None:
    text = clean_words(value)
    if text in UNKNOWN_VALUES:
        return None
    text = re.sub(r"\brose gold\b", "gold", text)
    replacements = {
        "navy": "blue", "sky": "blue", "cyan": "blue",
        "grey": "gray", "charcoal": "gray",
        "burgundy": "red", "maroon": "red",
        "beige": "brown", "tan": "brown",
        "violet": "purple", "lavender": "purple",
        "magenta": "pink", "fuchsia": "pink",
        "golden": "gold",
    }
    colours = {
        "black", "white", "gray", "red", "blue", "green", "yellow",
        "orange", "purple", "pink", "brown", "silver", "gold",
    }
    tokens = [replacements.get(token, token) for token in text.split()]
    identified = set(tokens).intersection(colours)
    return identified or None


def colour_pair_score(lost: str, found: str) -> float | None:
    a = normalize_colours(lost)
    b = normalize_colours(found)
    if a is None or b is None:
        return None
    return len(a & b) / len(a | b)  # Jaccard; supports multicolour reports.


def combined_text_score(
    lost_description: str,
    found_description: str,
    lost_ai_caption: str,
    found_ai_caption: str,
) -> tuple[float | None, dict]:
    """Prefer user-to-user (70%) and caption-to-caption (30%).

    If neither pair exists, compare user text against the opposite AI caption.
    Avoid counting a caption twice when the user copied it verbatim.
    """
    lost_user = (lost_description or "").strip()
    found_user = (found_description or "").strip()
    lost_ai = (lost_ai_caption or "").strip()
    found_ai = (found_ai_caption or "").strip()

    if lost_ai and clean_words(lost_ai) == clean_words(lost_user):
        lost_ai = ""
    if found_ai and clean_words(found_ai) == clean_words(found_user):
        found_ai = ""

    user_score = tfidf_pair_score(lost_user, found_user)
    caption_score = tfidf_pair_score(lost_ai, found_ai)
    cross_scores = [
        score for score in (
            tfidf_pair_score(lost_user, found_ai),
            tfidf_pair_score(lost_ai, found_user),
        ) if score is not None
    ]

    if user_score is not None and caption_score is not None:
        score = 0.70 * user_score + 0.30 * caption_score
        method = "user_and_ai"
    elif user_score is not None:
        score = user_score
        method = "user_only"
    elif caption_score is not None:
        score = caption_score
        method = "ai_only"
    elif cross_scores:
        score = max(cross_scores)
        method = "cross_user_ai_fallback"
    else:
        score = None
        method = "no_comparable_text"

    return score, {
        "method": method,
        "user_description_similarity": (
            round(user_score, 4) if user_score is not None else None
        ),
        "ai_caption_similarity": (
            round(caption_score, 4) if caption_score is not None else None
        ),
    }


def summarize_hybrid_scores(scores: dict[str, float | None]) -> tuple[float | None, dict]:
    """Re-normalize weights over available components; None != zero."""
    present = {
        key: score for key, score in scores.items()
        if score is not None
    }
    if not present:
        return None, {}
    weight_sum = sum(HYBRID_WEIGHTS[key] for key in present)
    effective_weights = {
        key: HYBRID_WEIGHTS[key] / weight_sum for key in present
    }
    overall = sum(
        effective_weights[key] * score for key, score in present.items()
    )
    return max(0.0, min(1.0, overall)), effective_weights


@app.post("/hybrid-match")
def hybrid_match(
    lost_image: UploadFile | None = File(default=None),
    found_image: UploadFile | None = File(default=None),
    lost_category: str = Form(default=""),
    found_category: str = Form(default=""),
    lost_description: str = Form(default=""),
    found_description: str = Form(default=""),
    lost_ai_caption: str = Form(default=""),
    found_ai_caption: str = Form(default=""),
    lost_model: str = Form(default=""),
    found_model: str = Form(default=""),
    lost_colour: str = Form(default=""),
    found_colour: str = Form(default=""),
):
    """Compare one Lost and one Found report; never automatically confirm ownership."""
    lost_cat = normalize_category(lost_category)
    found_cat = normalize_category(found_category)
    category_compatible = (
        lost_cat == found_cat if lost_cat and found_cat else None
    )
    if category_compatible is False:
        return {
            "success": True,
            "status": "category_mismatch",
            "category_compatible": False,
            "overall_similarity_score": None,
            "overall_similarity_percent": None,
            "component_scores": {},
            "effective_weights": {},
            "model_conflict": False,
            "note": "Known categories differ; not a candidate for matching.",
        }

    lost = load_uploaded_image(lost_image) if lost_image is not None else None
    found = load_uploaded_image(found_image) if found_image is not None else None

    image_cosine = None
    image_score = None
    if lost is not None and found is not None:
        lost_embedding = get_normalized_clip_embedding(lost)
        found_embedding = get_normalized_clip_embedding(found)
        image_cosine = float(torch.dot(lost_embedding, found_embedding).item())
        image_cosine = max(-1.0, min(1.0, image_cosine))
        # Use [0,1] for weighted aggregation; preserve raw cosine separately.
        image_score = max(0.0, image_cosine)

    # Automatically generate missing captions when images are available.
    # Production integration should store the caption once per item and pass it in.
    lost_caption_source = "provided" if lost_ai_caption.strip() else "missing"
    found_caption_source = "provided" if found_ai_caption.strip() else "missing"
    if lost is not None and not lost_ai_caption.strip():
        lost_ai_caption = generate_blip_caption(lost)
        lost_caption_source = "generated"
    if found is not None and not found_ai_caption.strip():
        found_ai_caption = generate_blip_caption(found)
        found_caption_source = "generated"

    text_score, text_details = combined_text_score(
        lost_description, found_description,
        lost_ai_caption, found_ai_caption,
    )
    model_score = model_pair_score(lost_model, found_model)
    colour_score = colour_pair_score(lost_colour, found_colour)
    component_scores = {
        "image": image_score,
        "text": text_score,
        "model": model_score,
        "colour": colour_score,
    }
    overall, effective_weights = summarize_hybrid_scores(component_scores)
    available_count = sum(score is not None for score in component_scores.values())
    status = (
        "insufficient_evidence" if available_count == 0 else
        "limited_evidence" if available_count < 2 else "compared"
    )

    return {
        "success": True,
        "status": status,
        "category_compatible": category_compatible,
        "model_conflict": model_score == 0.0,
        "overall_similarity_score": (
            round(overall, 4) if overall is not None else None
        ),
        "overall_similarity_percent": (
            round(overall * 100, 2) if overall is not None else None
        ),
        "image_cosine_similarity": (
            round(image_cosine, 4) if image_cosine is not None else None
        ),
        "component_scores": {
            key: (round(value, 4) if value is not None else None)
            for key, value in component_scores.items()
        },
        "effective_weights": {
            key: round(value, 4) for key, value in effective_weights.items()
        },
        "text_details": text_details,
        "ai_captions_used": {
            "lost": lost_ai_caption,
            "found": found_ai_caption,
        },
        "ai_caption_sources": {
            "lost": lost_caption_source,
            "found": found_caption_source,
        },
        "evidence_components_available": available_count,
        "note": (
            "Heuristic similarity score only, not a probability or proof of "
            "ownership. Do not notify automatically until reports are "
            "approved and notification thresholds are evaluated."
        ),
    }
