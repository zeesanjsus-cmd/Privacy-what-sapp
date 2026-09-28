require('dotenv').config();
const express=require('express'); const http=require('http'); const cors=require('cors'); const helmet=require('helmet'); const rateLimit=require('express-rate-limit'); const {Server}=require('socket.io'); const jwt=require('jsonwebtoken');
const app=express(); const server=http.createServer(app); const io=new Server(server,{cors:{origin:'*'}});
app.use(helmet()); app.use(cors()); app.use(express.json({limit:'2mb'})); app.use(rateLimit({windowMs:60000,max:120}));
const users=new Map(), reports=new Map(), audits=[];
app.get('/health',(req,res)=>res.json({ok:true,service:'privacy-whatsapp'}));
app.post('/auth/request-otp',(req,res)=>{const {phone}=req.body||{}; if(!phone)return res.status(400).json({error:'phone required'}); res.json({ok:true,message:'OTP request accepted; connect a real SMS provider in production'});});
app.post('/auth/verify-otp',(req,res)=>{const {phone,otp}=req.body||{}; if(!phone||!otp)return res.status(400).json({error:'phone and otp required'}); if(otp==='000000'){const id='demo-'+phone.replace(/\D/g,''); users.set(id,{id,phone,status:'active'}); const token=jwt.sign({sub:id,role:'user'},process.env.JWT_SECRET||'dev-only-secret'); return res.json({token,user:users.get(id)});} res.status(401).json({error:'Invalid OTP. Demo accepts 000000 only; replace with real provider.'});});
function auth(req,res,next){try{const h=req.headers.authorization||''; req.user=jwt.verify(h.replace('Bearer ',''),process.env.JWT_SECRET||'dev-only-secret'); next();}catch(e){res.status(401).json({error:'unauthorized'});}}
app.get('/me',auth,(req,res)=>res.json(users.get(req.user.sub)||{id:req.user.sub}));
app.post('/reports',auth,(req,res)=>{const r={id:Date.now().toString(),reporter:req.user.sub,target:req.body.target,reason:req.body.reason||'other',status:'open',createdAt:new Date().toISOString()};reports.set(r.id,r); audits.push({action:'report_created',actor:req.user.sub,target:r.target,at:r.createdAt});res.status(201).json(r);});
app.get('/owner/reports',(req,res)=>res.json([...reports.values()]));
app.post('/owner/users/:id/suspend',(req,res)=>{const u=users.get(req.params.id)||{id:req.params.id};u.status='suspended';users.set(u.id,u);audits.push({action:'suspend',target:u.id,at:new Date().toISOString()});res.json(u);});
app.post('/owner/users/:id/block',(req,res)=>{const u=users.get(req.params.id)||{id:req.params.id};u.status='blocked';users.set(u.id,u);audits.push({action:'block',target:u.id,at:new Date().toISOString()});res.json(u);});
app.post('/owner/users/:id/restore',(req,res)=>{const u=users.get(req.params.id)||{id:req.params.id};u.status='active';users.set(u.id,u);audits.push({action:'restore',target:u.id,at:new Date().toISOString()});res.json(u);});
app.get('/owner/users',(req,res)=>res.json([...users.values()])); app.get('/owner/audit-logs',(req,res)=>res.json(audits));
io.on('connection',socket=>{socket.on('join',room=>socket.join(room));socket.on('message',m=>{if(m?.room)io.to(m.room).emit('message',m);});socket.on('call:offer',m=>io.to(m?.room).emit('call:offer',m));socket.on('call:answer',m=>io.to(m?.room).emit('call:answer',m));socket.on('call:ice',m=>io.to(m?.room).emit('call:ice',m));});
server.listen(process.env.PORT||8080,()=>console.log('Privacy WhatsApp backend running'));
