package com.mich.autoclipsync;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.os.Build;
import android.os.IBinder;
import android.content.Intent;
import android.content.Context;
import android.content.ClipData;
import android.content.ClipboardManager;
import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

public class ClipBridgeService extends Service {
    static volatile String lastText = "";
    static volatile long lastChange = 0;
    static volatile String lastSource = "boot";
    static ClipBridgeService instance;
    ClipboardManager cm;
    ServerSocket server;
    boolean running = true;

    public IBinder onBind(Intent i) { return null; }
    public void onCreate() { super.onCreate(); instance=this; cm=(ClipboardManager)getSystemService(CLIPBOARD_SERVICE); startFg(); listen(); startPoll(); startHttp(); }
    public int onStartCommand(Intent i, int flags, int id) { if(i!=null && i.hasExtra("text")) setClip(i.getStringExtra("text"), "intent"); return START_STICKY; }
    public void onDestroy() { running=false; try{ if(server!=null) server.close(); }catch(Exception e){} super.onDestroy(); }

    void startFg() {
        if(Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel("sync", "MichAutoClipSync", NotificationManager.IMPORTANCE_LOW);
            ((NotificationManager)getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(ch);
        }
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, "sync") : new Notification.Builder(this);
        b.setContentTitle("MichAutoClipSync").setContentText("ADB bridge active on phone port 8765").setSmallIcon(com.mich.autoclipsync.R.drawable.ic_mich_auto_clip_sync_notify).setOngoing(true);
        startForeground(42, b.build());
    }

    void listen() { try { cm.addPrimaryClipChangedListener(new ClipboardManager.OnPrimaryClipChangedListener(){ public void onPrimaryClipChanged(){ readClip("listener"); }}); } catch(Exception e){ lastSource="listener_error:"+e.getClass().getSimpleName(); } }
    void startPoll() { Thread t=new Thread(new Runnable(){ public void run(){ while(running){ readClip("poll"); try{Thread.sleep(500);}catch(Exception e){} } }}); t.setDaemon(true); t.start(); }
    static String esc(String s) { if(s==null) return ""; return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r"); }
    public static void publishObservedText(String text, String src) { if(text==null) text=""; if(!text.equals(lastText)){ lastText=text; lastChange=System.currentTimeMillis(); lastSource=src; } }
    void readClip(String src) { try { if(cm!=null && cm.hasPrimaryClip()) { ClipData cd=cm.getPrimaryClip(); if(cd!=null && cd.getItemCount()>0) { CharSequence cs=cd.getItemAt(0).coerceToText(this); publishObservedText(cs==null?"":cs.toString(), src); } } } catch(Throwable t){ lastSource=src+"_blocked:"+t.getClass().getSimpleName(); } }
    public static void externalSet(Context c, String text) { if(instance!=null) instance.setClip(text, "broadcast"); else { Intent i=new Intent(c, ClipBridgeService.class); i.putExtra("text", text); if(Build.VERSION.SDK_INT>=26)c.startForegroundService(i); else c.startService(i); } }
    void setClip(String text, String src) { try { if(text==null) text=""; cm.setPrimaryClip(ClipData.newPlainText("MichAutoClipSync", text)); publishObservedText(text, src); } catch(Throwable t){ lastSource=src+"_set_blocked:"+t.getClass().getSimpleName(); } }

    void startHttp() { Thread t=new Thread(new Runnable(){ public void run(){ try { server=new ServerSocket(8765,10, InetAddress.getByName("127.0.0.1")); while(running) handle(server.accept()); } catch(Exception e){ lastSource="http_error:"+e.getClass().getSimpleName(); } }}); t.setDaemon(true); t.start(); }
    void handle(Socket s) {
        try {
            s.setSoTimeout(3000);
            BufferedInputStream in = new BufferedInputStream(s.getInputStream());
            ByteArrayOutputStream head = new ByteArrayOutputStream();
            int prev=0,b;
            while((b=in.read())!=-1){ head.write(b); if(prev=='\r' && b=='\n'){ byte[] h=head.toByteArray(); int n=h.length; if(n>=4 && h[n-4]=='\r' && h[n-3]=='\n' && h[n-2]=='\r' && h[n-1]=='\n') break; } prev=b; }
            String hs=head.toString("UTF-8"); String[] lines=hs.split("\r?\n"); String first=lines.length>0?lines[0]:""; int len=0;
            for(String l:lines){ int idx=l.indexOf(':'); if(idx>0 && l.substring(0,idx).equalsIgnoreCase("Content-Length")) len=Integer.parseInt(l.substring(idx+1).trim()); }
            byte[] body=new byte[len]; int off=0; while(off<len){ int r=in.read(body,off,len-off); if(r<0)break; off+=r; }
            String[] parts=first.split(" "); String method=parts.length>0?parts[0]:"GET"; String path=parts.length>1?parts[1]:"/"; String resp; String type="text/plain; charset=utf-8"; int code=200;
            if(path.startsWith("/status")){ type="application/json"; resp="{\"ok\":true,\"lastChange\":"+lastChange+",\"lastSource\":\""+esc(lastSource)+"\",\"length\":"+(lastText==null?0:lastText.length())+"}"; }
            else if(path.startsWith("/clip") && method.equals("GET")){ resp=lastText==null?"":lastText; }
            else if(path.startsWith("/clip") && method.equals("POST")){ String txt=new String(body,0,off, StandardCharsets.UTF_8); setClip(txt,"http"); resp="OK "+txt.length(); }
            else { code=404; resp="not found"; }
            byte[] rb=resp.getBytes(StandardCharsets.UTF_8); OutputStream out=s.getOutputStream(); out.write(("HTTP/1.1 "+code+" OK\r\nContent-Type: "+type+"\r\nContent-Length: "+rb.length+"\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8)); out.write(rb); out.flush();
        } catch(Exception e) {}
        try { s.close(); } catch(Exception e) {}
    }
}
