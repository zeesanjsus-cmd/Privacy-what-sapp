# Security model

1. Use HTTPS everywhere and a strong secrets manager.
2. Real OTP provider with rate limits, resend limits and fraud controls.
3. Store tokens in platform secure storage; rotate refresh tokens.
4. Add device/session management and remote logout.
5. Use object storage with private buckets and short-lived signed URLs.
6. Add TURN for reliable WebRTC calls.
7. Add WAF, database backups, monitoring and alerting.
8. Never hard-code owner passwords or API keys.
9. Owner/admin actions must be authenticated with MFA/passkeys and written to audit_logs.
10. If moderation requires reading message content, do not claim the system is true end-to-end encrypted for those messages.
11. Do not promise 100% unhackable security; commission an independent security review before launch.
