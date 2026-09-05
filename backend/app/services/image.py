import os
import io
from uuid import UUID

from PIL import Image

from app.config import get_settings

settings = get_settings()
MAX_IMAGE_SIZE = 2 * 1024 * 1024  # 2MB
MAX_DIMENSION = 480
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}


def validate_image(content_type: str, size: int) -> None:
    if content_type not in ALLOWED_TYPES:
        raise ValueError(f"Unsupported image type: {content_type}")
    if size > MAX_IMAGE_SIZE:
        raise ValueError(f"Image too large: {size} bytes (max {MAX_IMAGE_SIZE})")


def compress_image(data: bytes) -> tuple[bytes, str]:
    img = Image.open(io.BytesIO(data))
    img = img.convert("RGB")

    if max(img.size) > MAX_DIMENSION:
        ratio = MAX_DIMENSION / max(img.size)
        new_size = (int(img.size[0] * ratio), int(img.size[1] * ratio))
        img = img.resize(new_size, Image.LANCZOS)

    output = io.BytesIO()
    img.save(output, format="WEBP", quality=60, method=4)
    return output.getvalue(), "webp"


def save_image(card_id: UUID, data: bytes, ext: str) -> str:
    filename = f"{card_id}.{ext}"
    filepath = os.path.join(settings.MEDIA_ROOT, filename)
    os.makedirs(settings.MEDIA_ROOT, exist_ok=True)
    with open(filepath, "wb") as f:
        f.write(data)
    return f"{settings.MEDIA_URL}/{filename}"


def delete_image(image_path: str) -> None:
    if not image_path:
        return
    filepath = image_path.replace(settings.MEDIA_URL, settings.MEDIA_ROOT)
    real_media = os.path.realpath(settings.MEDIA_ROOT)
    real_filepath = os.path.realpath(filepath)
    if not real_filepath.startswith(real_media + os.sep) and real_filepath != real_media:
        return
    if os.path.exists(real_filepath):
        os.remove(real_filepath)
