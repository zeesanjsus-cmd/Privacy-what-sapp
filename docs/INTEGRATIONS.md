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


## 8. Monetization and rewards
The app should have transparent, non-pyramid revenue sources. The owner can earn from:
- optional in-app ads (when enabled and compliant with Google Play policies)
- optional paid Premium/Business subscriptions
- paid business features or storage tiers
- other clearly disclosed purchases approved by the payment provider

Users can have a Rewards/Points screen for legitimate actions such as completing profile/setup or promotional campaigns. Rewards must not require users to recruit or pay money to unlock commissions. The database records reward transactions and owner revenue events separately so user rewards and business revenue remain auditable.

Do not promise users a cash reward unless a real payment/reward provider and its terms are configured. Payment provider credentials and merchant verification are required before charging users.

## 9. Owner dashboard
Add an owner-only dashboard section showing total users, active users, subscriptions, ad/revenue events, reward points issued, and recent transactions. Revenue numbers should be based on recorded provider-confirmed events, not guesses.
