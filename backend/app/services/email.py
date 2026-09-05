import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from app.config import get_settings


def send_verification_email(to_email: str, verification_url: str) -> bool:
    """Send a verification email. Returns True if sent successfully."""
    settings = get_settings()

    if not settings.SMTP_HOST or not settings.SMTP_USER:
        return False

    msg = MIMEMultipart("alternative")
    msg["Subject"] = "Подтвердите ваш email — Карточки"
    msg["From"] = settings.EMAIL_FROM
    msg["To"] = to_email

    html = f"""
    <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; padding: 32px;">
        <h2 style="color: #333;">Подтвердите email</h2>
        <p style="color: #555; line-height: 1.6;">
            Вы зарегистрировались в приложении <strong>Карточки</strong>.
            Нажмите кнопку ниже, чтобы подтвердить ваш email:
        </p>
        <a href="{verification_url}"
           style="display: inline-block; background: #4a90d9; color: white;
                  padding: 12px 32px; border-radius: 8px; text-decoration: none;
                  font-weight: bold; margin: 16px 0;">
            Подтвердить email
        </a>
        <p style="color: #999; font-size: 13px; margin-top: 24px;">
            Ссылка действует 24 часа. Если вы не регистрировались,
            просто проигнорируйте это письмо.
        </p>
    </div>
    """

    text = f"Подтвердите email: {verification_url}"

    msg.attach(MIMEText(text, "plain"))
    msg.attach(MIMEText(html, "html"))

    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
            server.ehlo()
            if settings.SMTP_PORT != 25:
                server.starttls()
                server.ehlo()
            if settings.SMTP_USER and settings.SMTP_PASSWORD:
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            server.sendmail(settings.EMAIL_FROM, to_email, msg.as_string())
        return True
    except Exception:
        return False
