# Production integrations

## 1. SMS OTP
Set these backend variables:
- SMS_PROVIDER=twilio
- TWILIO_ACCOUNT_SID
- TWILIO_AUTH_TOKEN
- TWILIO_VERIFY_SERVICE_SID

The backend stores only a salted/hash-derived OTP value and expires OTPs after 5 minutes. Demo/console OTP is for local testing only.

## 2. PostgreSQL
Run database/schema.sql against the production PostgreSQL database and set DATABASE_URL.

## 3. Push notifications
Create a Firebase Android app and place its google-services.json in the Flutter Android project. Configure backend:
- FCM_ENABLED=true
- FCM_SERVICE_ACCOUNT_JSON=<Firebase service-account JSON>

Never commit the service-account JSON or SMS credentials to GitHub.

## 4. API URL
Build the Flutter APK with:
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-API-DOMAIN

The API must use HTTPS in production.

## 5. Calls
The current server provides authenticated Socket.IO signaling events. For reliable voice/video calls, add WebRTC on mobile and a TURN server. Configure the TURN credentials outside the repository.

## 6. Media
Use private object storage (S3-compatible or equivalent) with short-lived signed upload/download URLs. Do not put permanent public media URLs in chat messages.

## 7. Owner
Set OWNER_PHONE to the owner's verified international phone number. Owner/admin API routes require an authenticated JWT with owner/admin role.

## 8. Security
Use a long random JWT_SECRET and OTP_PEPPER. Restrict CORS to the production app/API origins. Put the backend behind HTTPS and a reverse proxy/WAF. Rotate provider credentials and monitor audit_logs.

## Important
The repository contains integration adapters and production-safe defaults, but third-party accounts (SMS/Firebase/storage/TURN) must be created by the owner because they require the owner's credentials and billing/terms acceptance.
