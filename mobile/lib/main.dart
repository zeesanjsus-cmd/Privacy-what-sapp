import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

const red=Color(0xFFE53935), black=Color(0xFF080808), panel=Color(0xFF151515);
const apiBaseUrl=String.fromEnvironment('API_BASE_URL',defaultValue:'http://10.0.2.2:8080');
const storage=FlutterSecureStorage();

class Api {
  Future<Map<String,String>> headers() async {
    final t=await storage.read(key:'token');
    return {'Content-Type':'application/json',if(t!=null)'Authorization':'Bearer '+t};
  }
  Future<dynamic> get(String path) async {
    final r=await http.get(Uri.parse(apiBaseUrl+path),headers:await headers());
    if(r.statusCode>=400) throw Exception(_err(r));
    return jsonDecode(r.body);
  }
  Future<dynamic> post(String path,Map<String,dynamic> body) async {
    final r=await http.post(Uri.parse(apiBaseUrl+path),headers:await headers(),body:jsonEncode(body));
    if(r.statusCode>=400) throw Exception(_err(r));
    return jsonDecode(r.body);
  }
  String _err(http.Response r){try{return jsonDecode(r.body)['error']??'Request failed';}catch(_){return 'Request failed';}}
}
final api=Api();

Future<void> initPush() async {
  try {
    await Firebase.initializeApp();
    final m=FirebaseMessaging.instance;
    await m.requestPermission(alert:true,badge:true,sound:true);
    final t=await m.getToken();
    if(t!=null && await storage.read(key:'token')!=null){
      await api.post('/devices',{'pushToken':t,'platform':'android','deviceName':'Android device'});
    }
    m.onTokenRefresh.listen((token) async {
      if(await storage.read(key:'token')!=null){
        try{await api.post('/devices',{'pushToken':token,'platform':'android','deviceName':'Android device'});}catch(_){}
      }
    });
  }catch(_){}
}

void main(){WidgetsFlutterBinding.ensureInitialized();runApp(const App());}

class App extends StatelessWidget{
 const App({super.key});
 @override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,title:'Privacy WhatsApp',
 theme:ThemeData(brightness:Brightness.dark,scaffoldBackgroundColor:black,colorScheme:ColorScheme.dark(primary:red),useMaterial3:true),
 home:const Login());
}

class Login extends StatefulWidget{const Login({super.key});@override State<Login> createState()=>_LoginState();}
class _LoginState extends State<Login>{
 final phone=TextEditingController(),otp=TextEditingController();bool sent=false,busy=false;String error='';
 Future<void> submit() async{
  setState((){busy=true;error='';});
  try{
   final p='+92'+phone.text.replaceAll(RegExp(r'\\D'),'');
   if(!sent){await api.post('/auth/request-otp',{'phone':p});setState(()=>sent=true);}
   else{
    final r=await api.post('/auth/verify-otp',{'phone':p,'otp':otp.text.trim()});
    await storage.write(key:'token',value:r['token']);
    await storage.write(key:'userId',value:r['user']['id']);
    await initPush();
    if(mounted)Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const Home()));
   }
  }catch(e){setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext c)=>Scaffold(body:SafeArea(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
 const SizedBox(height:35),const Icon(Icons.chat_bubble_rounded,size:90,color:red),const SizedBox(height:20),
 const Text('Privacy WhatsApp',textAlign:TextAlign.center,style:TextStyle(fontSize:30,fontWeight:FontWeight.bold)),
 const Text('Private • Business • Secure',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60)),const SizedBox(height:45),
 TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Pakistan mobile number',prefixText:'+92 ',filled:true,fillColor:panel,border:OutlineInputBorder())),
 if(sent)Padding(padding:const EdgeInsets.only(top:15),child:TextField(controller:otp,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'6-digit OTP',filled:true,fillColor:panel,border:OutlineInputBorder()))),
 if(error.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Text(error,textAlign:TextAlign.center,style:const TextStyle(color:red))),
 const SizedBox(height:20),ElevatedButton(onPressed:busy?null:submit,style:ElevatedButton.styleFrom(backgroundColor:red,foregroundColor:Colors.white,padding:const EdgeInsets.all(16)),child:busy?const SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2)):Text(sent?'Verify OTP':'Send OTP'))
]))));
 }
}

class Home extends StatefulWidget{const Home({super.key});@override State<Home> createState()=>_HomeState();}
class _HomeState extends State<Home>{int tab=0;final pages=const[Chats(),Status(),Calls(),Settings()];
 @override Widget build(BuildContext c)=>Scaffold(body:pages[tab],bottomNavigationBar:NavigationBar(backgroundColor:panel,selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),
 destinations:const[NavigationDestination(icon:Icon(Icons.chat_bubble_outline),label:'Chats'),NavigationDestination(icon:Icon(Icons.circle_outlined),label:'Status'),NavigationDestination(icon:Icon(Icons.call_outlined),label:'Calls'),NavigationDestination(icon:Icon(Icons.settings_outlined),label:'Settings')]));
}

class Chats extends StatefulWidget{const Chats({super.key});@override State<Chats> createState()=>_ChatsState();}
class _ChatsState extends State<Chats>{
 List data=[];bool loading=true;
 Future<void> load()async{try{data=await api.get('/conversations');}catch(_){}if(mounted)setState(()=>loading=false);}
 @override void initState(){super.initState();load();}
 Future<void> start()async{
  try{
   final users=await api.get('/users');if(!mounted)return;
   showModalBottomSheet(context:context,backgroundColor:panel,builder:(_)=>ListView(children:[
    const Padding(padding:EdgeInsets.all(18),child:Text('Start a chat',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
    for(final u in users)ListTile(leading:const CircleAvatar(backgroundColor:red,child:Icon(Icons.person)),
     title:Text(u['display_name']??'User'),subtitle:Text(u['phone']),onTap:()async{
      Navigator.pop(context);final r=await api.post('/conversations/direct',{'userId':u['id']});
      if(mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>Chat(id:r['id'],name:u['display_name']??u['phone']))).then((_)=>load());
     })
   ]));
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Privacy WhatsApp'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
 floatingActionButton:FloatingActionButton(backgroundColor:red,onPressed:start,child:const Icon(Icons.add_comment)),
 body:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:load,child:data.isEmpty?ListView(children:const[ SizedBox(height:180),Center(child:Text('No chats yet. Tap + to start.'))]):ListView(children:[
  for(final x in data)ListTile(leading:const CircleAvatar(backgroundColor:red,child:Icon(Icons.person)),title:Text(x['title']??'Chat'),subtitle:Text(x['last_message']??'No messages yet'),
  onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>Chat(id:x['id'],name:x['title']??'Chat'))).then((_)=>load())
 ])));
}

class Chat extends StatefulWidget{
  final String id;
  final String name;
  const Chat({super.key, required this.id, required this.name});
  @override State<Chat> createState()=>_ChatState();
}

class _ChatState extends State<Chat>{
  final input=TextEditingController();
  List<dynamic> messages=[];
  bool loading=true;

  Future<void> load() async {
    try {
      final result=await api.get('/conversations/${widget.id}/messages');
      if(result is List) messages=result;
    } catch (_) {}
    if(mounted) setState(()=>loading=false);
  }

  Future<void> send() async {
    final body=input.text.trim();
    if(body.isEmpty) return;
    input.clear();
    try {
      final result=await api.post('/conversations/${widget.id}/messages', {'body':body,'messageType':'text'});
      if(mounted) setState(()=>messages=[...messages,result]);
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    }
  }

  @override void initState(){super.initState();load();}
  @override void dispose(){input.dispose();super.dispose();}

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.name),actions:[
      IconButton(onPressed:(){},icon:const Icon(Icons.call)),
      IconButton(onPressed:(){},icon:const Icon(Icons.videocam)),
    ]),
    body:Column(children:[
      Expanded(child:loading
        ? const Center(child:CircularProgressIndicator())
        : ListView.builder(
            padding:const EdgeInsets.all(12),
            itemCount:messages.length,
            itemBuilder:(context,index)=>Align(
              alignment:Alignment.centerLeft,
              child:Container(
                margin:const EdgeInsets.symmetric(vertical:4),
                padding:const EdgeInsets.all(12),
                decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(16)),
                child:Text(messages[index]['body']??''),
              ),
            ),
          )),
      Container(color:panel,padding:const EdgeInsets.all(8),child:Row(children:[
        IconButton(onPressed:(){},icon:const Icon(Icons.attach_file)),
        Expanded(child:TextField(
          controller:input,
          onSubmitted:(_)=>send(),
          decoration:InputDecoration(hintText:'Message',filled:true,fillColor:black,border:OutlineInputBorder(borderRadius:BorderRadius.circular(25))),
        )),
        IconButton(onPressed:send,icon:const Icon(Icons.send,color:red)),
      ])),
    ]),
  );
}

class Status extends StatelessWidget{const Status({super.key});@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Status')),floatingActionButton:FloatingActionButton(backgroundColor:red,onPressed:(){},child:const Icon(Icons.add)),body:const Center(child:Text('Status module ready for media storage integration.')));}
class Calls extends StatelessWidget{const Calls({super.key});@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Calls')),body:const Center(child:Text('Call signaling foundation is ready; WebRTC/TURN credentials are required for live media.')));}
class Settings extends StatelessWidget{const Settings({super.key});
 Future<void> logout(BuildContext c)async{await storage.delete(key:'token');await storage.delete(key:'userId');if(c.mounted)Navigator.pushAndRemoveUntil(c,MaterialPageRoute(builder:(_)=>const Login()),(_)=>false);}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Settings')),body:ListView(children:[
 const UserAccountsDrawerHeader(decoration:BoxDecoration(color:panel),currentAccountPicture:CircleAvatar(backgroundColor:red,child:Icon(Icons.person)),accountName:Text('Your account'),accountEmail:Text('OTP authenticated')),
 const ListTile(leading:Icon(Icons.lock),title:Text('Privacy'),subtitle:Text('Privacy and blocked users')),const ListTile(leading:Icon(Icons.notifications),title:Text('Notifications'),subtitle:Text('Firebase push notifications')),
 const ListTile(leading:Icon(Icons.security),title:Text('Security'),subtitle:Text('Device sessions and alerts')),const ListTile(leading:Icon(Icons.business),title:Text('Business tools')),
 ListTile(leading:const Icon(Icons.logout,color:red),title:const Text('Log out'),onTap:()=>logout(c))
 ]));}
