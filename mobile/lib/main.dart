import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

const red = Color(0xFFE53935);
const black = Color(0xFF080808);
const panel = Color(0xFF151515);
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');
const apiBaseConfigured = String.fromEnvironment('API_BASE_URL', defaultValue: '') != '';
const storage = FlutterSecureStorage();

class Api {
  Future<Map<String, String>> headers() async {
    final token = await storage.read(key: 'token');
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }
  Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$apiBaseUrl$path'), headers: await headers());
    if (r.statusCode >= 400) throw Exception(_err(r));
    return jsonDecode(r.body);
  }
  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final r = await http.post(Uri.parse('$apiBaseUrl$path'), headers: await headers(), body: jsonEncode(body));
    if (r.statusCode >= 400) throw Exception(_err(r));
    return jsonDecode(r.body);
  }
  Future<dynamic> upload(String path, XFile file) async {
    final token = await storage.read(key: 'token');
    final request = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl$path'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', file.path, filename: file.name));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 400) throw Exception(_err(response));
    return jsonDecode(response.body);
  }
  String _err(http.Response r) {
    try { return jsonDecode(r.body)['error'] ?? 'Request failed'; } catch (_) { return 'Request failed'; }
  }
}
final api = Api();

Future<void> initPush() async {
  try {
    await Firebase.initializeApp();
    final m = FirebaseMessaging.instance;
    await m.requestPermission(alert: true, badge: true, sound: true);
    final t = await m.getToken();
    if (t != null && await storage.read(key: 'token') != null) {
      await api.post('/devices', {'pushToken': t, 'platform': 'android', 'deviceName': 'Android device'});
    }
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Privacy WhatsApp',
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: black, colorScheme: ColorScheme.dark(primary: red), useMaterial3: true),
      home: const Login(),
    );
  }
}

class Login extends StatefulWidget {
  const Login({super.key});
  @override State<Login> createState() => _LoginState();
}
class _LoginState extends State<Login> {
  final phone = TextEditingController();
  final otp = TextEditingController();
  bool sent = false, busy = false;
  String error = '';

  Future<void> submit() async {
    setState(() { busy = true; error = ''; });
    try {
      final digits = phone.text.replaceAll(RegExp(r'\D'), '');
      final normalized = digits.startsWith('0') ? digits.substring(1) : digits;
      final number = '+92$normalized';
      if (!sent) {
        await api.post('/auth/request-otp', {'phone': number});
        setState(() => sent = true);
      } else {
        final r = await api.post('/auth/verify-otp', {'phone': number, 'otp': otp.text.trim()});
        await storage.write(key: 'token', value: r['token']);
        await storage.write(key: 'userId', value: r['user']['id']);
        await initPush();
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Home()));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override void dispose() { phone.dispose(); otp.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 35),
            const Icon(Icons.chat_bubble_rounded, size: 90, color: red),
            const SizedBox(height: 20),
            const Text('Privacy WhatsApp', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const Text('Private • Business • Secure', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 45),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Pakistan mobile number', prefixText: '+92 ', filled: true, fillColor: panel, border: OutlineInputBorder())),
            if (sent) Padding(
              padding: const EdgeInsets.only(top: 15),
              child: TextField(controller: otp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6-digit OTP', filled: true, fillColor: panel, border: OutlineInputBorder())),
            ),
            if (error.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: red)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: busy ? null : submit,
              style: ElevatedButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
              child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(sent ? 'Verify OTP' : 'Send OTP'),
            ),
          ]),
        ),
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  int tab = 0;
  final pages = const [Chats(), Status(), Calls(), Settings()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        backgroundColor: panel, selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.circle_outlined), label: 'Status'),
          NavigationDestination(icon: Icon(Icons.call_outlined), label: 'Calls'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class Chats extends StatefulWidget {
  const Chats({super.key});
  @override State<Chats> createState() => _ChatsState();
}
class _ChatsState extends State<Chats> {
  List<dynamic> data = [];
  bool loading = true;
  Future<void> load() async {
    try { final r = await api.get('/conversations'); if (r is List) data = r; } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override void initState() { super.initState(); load(); }

  Future<void> start() async {
    try {
      final users = await api.get('/users');
      if (!mounted) return;
      showModalBottomSheet(
        context: context, backgroundColor: panel,
        builder: (_) => ListView(children: [
          const Padding(padding: EdgeInsets.all(18), child: Text('Start a chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          for (final u in users) ListTile(
            leading: const CircleAvatar(backgroundColor: red, child: Icon(Icons.person)),
            title: Text(u['display_name'] ?? 'User'), subtitle: Text(u['phone'] ?? ''),
            onTap: () async {
              Navigator.pop(context);
              final r = await api.post('/conversations/direct', {'userId': u['id']});
              if (mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => Chat(id: r['id'], name: u['display_name'] ?? u['phone']))).then((_) => load());
              }
            },
          ),
        ]),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = data.isEmpty
        ? ListView(children: const [SizedBox(height: 180), Center(child: Text('No chats yet. Tap + to start.'))])
        : ListView(children: [
            for (final x in data) ListTile(
              leading: const CircleAvatar(backgroundColor: red, child: Icon(Icons.person)),
              title: Text(x['title'] ?? 'Chat'), subtitle: Text(x['last_message'] ?? 'No messages yet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Chat(id: x['id'], name: x['title'] ?? 'Chat'))).then((_) => load()),
            ),
          ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy WhatsApp'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
      floatingActionButton: FloatingActionButton(backgroundColor: red, onPressed: start, child: const Icon(Icons.add_comment)),
      body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: list),
    );
  }
}

class Chat extends StatefulWidget {
  final String id;
  final String name;
  const Chat({super.key, required this.id, required this.name});
  @override State<Chat> createState() => _ChatState();
}
class _ChatState extends State<Chat> {
  final input = TextEditingController();
  List<dynamic> messages = [];
  bool loading = true;
  String? myUserId;
  Future<void> load() async {
    try {
      final me = await api.get('/me');
      myUserId = me['id']?.toString();
      final r = await api.get('/conversations/${widget.id}/messages');
      if (r is List) messages = r;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  Future<void> send() async {
    final body = input.text.trim();
    if (body.isEmpty) return;
    input.clear();
    try {
      final r = await api.post('/conversations/${widget.id}/messages', {'body': body, 'messageType': 'text'});
      if (mounted) setState(() => messages = [...messages, r]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    try {
      final uploaded = await api.upload('/media/upload', file);
      final r = await api.post('/conversations/${widget.id}/messages', {
        'body': '', 'mediaUrl': uploaded['url'], 'messageType': 'image'
      });
      if (mounted) setState(() => messages = [...messages, r]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override void initState() { super.initState(); load(); }
  @override void dispose() { input.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name), actions: [
        IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(name: widget.name, video: false))), icon: const Icon(Icons.call)),
        IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(name: widget.name, video: true))), icon: const Icon(Icons.videocam)),
      ]),
      body: Column(children: [
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(12), itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final senderId = (m['sender_id'] ?? m['senderId'])?.toString();
                    final mine = myUserId != null && senderId == myUserId;
                    final media = m['media_url'] ?? m['mediaUrl'];
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: mine ? red.withOpacity(.22) : panel,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: media != null
                            ? Image.network(
                                media.toString(), width: 220, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Text('Image unavailable'),
                              )
                            : Text(m['body'] ?? ''),
                      ),
                    );
                  },
                ),
        ),
        Container(color: panel, padding: const EdgeInsets.all(8), child: Row(children: [
          IconButton(onPressed: pickImage, icon: const Icon(Icons.attach_file)),
          Expanded(child: TextField(controller: input, onSubmitted: (_) => send(), decoration: InputDecoration(hintText: 'Message', filled: true, fillColor: black, border: OutlineInputBorder(borderRadius: BorderRadius.circular(25))))),
          IconButton(onPressed: send, icon: const Icon(Icons.send, color: red)),
        ])),
      ]),
    );
  }
}

class Status extends StatefulWidget {
  const Status({super.key});
  @override State<Status> createState() => _StatusState();
}

class _StatusState extends State<Status> {
  List<dynamic> items = [];
  bool loading = true;
  final caption = TextEditingController();

  Future<void> load() async {
    try {
      final r = await api.get('/statuses');
      if (r is List) items = r;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> addStatus() async {
    caption.clear();
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: panel,
        title: const Text('New status'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: caption,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Write a status...'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'image'),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose image'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(context, 'text'),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'image') {
        final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (file == null) return;
        final uploaded = await api.upload('/media/upload', file);
        await api.post('/statuses', {
          'mediaUrl': uploaded['url'],
          'caption': caption.text.trim(),
        });
      } else if (caption.text.trim().isNotEmpty) {
        await api.post('/statuses', {'caption': caption.text.trim()});
      }
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> deleteStatus(String id) async {
    try {
      await api.delete('/statuses/$id');
      await load();
    } catch (_) {}
  }

  @override void initState() { super.initState(); load(); }
  @override void dispose() { caption.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Status'), actions: [
        IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: red, onPressed: addStatus, child: const Icon(Icons.add),
      ),
      body: loading
        ? const Center(child: CircularProgressIndicator())
        : items.isEmpty
          ? const Center(child: Text('No status yet. Tap + to post.'))
          : RefreshIndicator(
              onRefresh: load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final x = items[i];
                  return Card(
                    color: panel,
                    child: ListTile(

                      subtitle: Text('Expires in 24 hours'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: (x['media_url'] ?? x['mediaUrl']) != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                (x['media_url'] ?? x['mediaUrl']).toString(),
                                width: 54, height: 54, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const CircleAvatar(backgroundColor: red, child: Icon(Icons.image)),
                              ),
                            )
                          : const CircleAvatar(backgroundColor: red, child: Icon(Icons.person)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => deleteStatus(x['id'].toString()),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class CallScreen extends StatefulWidget {
  final String name;
  final bool video;
  const CallScreen({super.key, required this.name, required this.video});
  @override State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool muted = false;
  bool speaker = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: black,
      appBar: AppBar(title: Text(widget.video ? 'Video call' : 'Voice call')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircleAvatar(radius: 58, backgroundColor: red, child: Icon(Icons.person, size: 58)),
                const SizedBox(height: 18),
                Text(widget.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Connecting…', style: TextStyle(color: Colors.white60)),
                if (widget.video) ...[
                  const SizedBox(height: 28),
                  const Text('Camera preview will start after WebRTC/TURN setup.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                ],
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 10, 30, 35),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton.filled(
                onPressed: () => setState(() => muted = !muted),
                icon: Icon(muted ? Icons.mic_off : Icons.mic), 
              ),
              IconButton.filled(
                onPressed: () => setState(() => speaker = !speaker),
                icon: Icon(speaker ? Icons.volume_up : Icons.volume_down),
              ),
              FloatingActionButton(
                backgroundColor: Colors.red,
                onPressed: () => Navigator.pop(context),
                child: const Icon(Icons.call_end),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class Calls extends StatelessWidget {
  const Calls({super.key});
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calls')),
    body: ListView(children: const [
      ListTile(leading: CircleAvatar(backgroundColor: red, child: Icon(Icons.call)), title: Text('Call history'), subtitle: Text('Your recent calls will appear here.')),
      ListTile(leading: Icon(Icons.info_outline), title: Text('Live calling setup'), subtitle: Text('WebRTC + TURN server is required for real voice/video media.')),
    ]),
  );
}

class Settings extends StatelessWidget {
  const Settings({super.key});
  Future<void> logout(BuildContext context) async {
    await storage.delete(key: 'token'); await storage.delete(key: 'userId');
    if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Login()), (_) => false);
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(children: const [
      UserAccountsDrawerHeader(
        decoration: BoxDecoration(color: panel),
        currentAccountPicture: CircleAvatar(backgroundColor: red, child: Icon(Icons.person)),
        accountName: Text('Your account'), accountEmail: Text('OTP authenticated'),
      ),
      ListTile(leading: Icon(Icons.lock), title: Text('Privacy'), subtitle: Text('Privacy and blocked users')),
      ListTile(leading: Icon(Icons.notifications), title: Text('Notifications'), subtitle: Text('Firebase push notifications')),
      ListTile(leading: Icon(Icons.security), title: Text('Security'), subtitle: Text('Device sessions and alerts')),
      ListTile(leading: Icon(Icons.business), title: Text('Business tools')),
    ]),
  );
}
