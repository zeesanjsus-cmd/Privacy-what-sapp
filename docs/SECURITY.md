# Security model

1. Use HTTPS everywhere and a strong secrets manager.
2. Real OTP provider with rate limits, resend limits and fraud controls.
3. Store tokens in platform secure storage; rotate refresh tokens.
4. Add device/session management and remote logout.
5. Use private object storage and short-lived signed URLs.
6. Add TURN for reliable WebRTC calls.
7. Add WAF, database backups, monitoring and alerting.
8. Never hard-code owner passwords or API keys.
9. Owner/admin actions must be authenticated with MFA/passkeys and written to audit logs.
10. If moderation requires reading message content, do not claim those messages are true end-to-end encrypted.
11. Do not promise 100% unhackable security; commission independent review before launch.
