# Privacy WhatsApp — Full MVP Project

A dark-interface WhatsApp-style business messaging app foundation with red branding and an Owner/Admin moderation console.

## Included
- Phone number + OTP login flow (provider adapter placeholder)
- Dark/black Flutter UI
- Red app branding/logo asset
- Chats, chat composer, attachments UI
- Status/Stories UI
- Voice/video call UI + WebRTC signaling foundation
- Settings, privacy, security, devices, account deletion screens
- Report/block user flows
- Node.js/Express + Socket.IO backend
- PostgreSQL schema for users, devices, conversations, messages, statuses, reports, blocks, calls, audit logs
- Owner/Admin API: reports, users, block/suspend/restore, audit logs
- Admin web dashboard
- Docker Compose for PostgreSQL + Redis
- Security/deployment/OTP/FCM/TURN documentation

## Important
This is a full MVP/production foundation, not a magically deployed service. Real SMS OTP, push notifications, media storage, TURN servers, domain/HTTPS, cloud database, and Play Console credentials must be connected before public release.

Do not advertise the service as 100% hack-proof. Security requires ongoing testing, monitoring, patching and independent review.
