# Required real integrations before launch

- SMS/OTP: choose a legitimate SMS provider and implement request/verify adapters.
- Push: Firebase Cloud Messaging for Android; APNs for iOS if iOS is later added.
- Media: S3-compatible private object storage.
- Calls: WebRTC + TURN server (coturn is a common option).
- Production database: managed PostgreSQL with backups.
- Domain: HTTPS certificate and API domain.
- Monitoring: error tracking, uptime and security alerts.
