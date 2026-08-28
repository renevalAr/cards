import httpx
from app.config import get_settings

settings = get_settings()


async def send_email(to: str, subject: str, html_body: str) -> bool:
    if not settings.EMAIL_API_KEY:
        return False

    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                "https://api.sendgrid.com/v3/mail/send",
                headers={"Authorization": f"Bearer {settings.EMAIL_API_KEY}"},
                json={
                    "personalizations": [{"to": [{"email": to}]}],
                    "from": {"email": settings.EMAIL_FROM},
                    "subject": subject,
                    "content": [{"type": "text/html", "value": html_body}],
                },
                timeout=10.0,
            )
            return response.status_code == 202
    except Exception:
        return False


async def send_verification_email(to: str, token: str) -> bool:
    subject = "Подтверждение регистрации — Карточки"
    html_body = f"""
    <h2>Добро пожаловать в Карточки!</h2>
    <p>Для подтверждения регистрации перейдите по ссылке:</p>
    <p><a href="http://localhost/verify?token={token}">Подтвердить email</a></p>
    <p>Если вы не регистрировались, проигнорируйте это письмо.</p>
    """
    return await send_email(to, subject, html_body)
