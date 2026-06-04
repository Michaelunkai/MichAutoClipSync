using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Management;
using System.Net;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace MichAutoClipSyncTray {
static class Program { static Mutex mutex; [STAThread] static void Main(){ bool created; mutex=new Mutex(true,"Global\\MichAutoClipSyncTray",out created); if(!created)return; Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false); Application.Run(new TrayContext()); } }
class TrayContext:ApplicationContext{
 string Root,Runner,Log; NotifyIcon icon; System.Windows.Forms.Timer timer; int runnerPid; string lastStatus="starting";
 public TrayContext(){Root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\'); Runner=Path.Combine(Root,"Start-MichAutoClipSync.ps1"); Log=Path.Combine(Root,"artifacts","proof","tray.log"); Directory.CreateDirectory(Path.GetDirectoryName(Log)); icon=new NotifyIcon(); icon.Text="MichAutoClipSync"; icon.Icon=MakeIcon(Color.LimeGreen); icon.Visible=true; icon.ContextMenuStrip=Menu(); icon.DoubleClick+=(s,e)=>ShowStatus(); LogLine("TRAY_START root="+Root); EnsureSingleRunner(); timer=new System.Windows.Forms.Timer(); timer.Interval=5000; timer.Tick+=(s,e)=>{try{EnsureSingleRunner();RefreshStatus();}catch(Exception ex){LogLine("TICK_ERR "+ex.Message);}}; timer.Start();}
 ContextMenuStrip Menu(){var m=new ContextMenuStrip(); m.Items.Add("Status",null,(s,e)=>ShowStatus()); m.Items.Add("Restart sync",null,(s,e)=>{KillRunners();StartRunner();Thread.Sleep(1500);RefreshStatus();ShowStatus();}); m.Items.Add("Open project folder",null,(s,e)=>Process.Start("explorer.exe",Root)); m.Items.Add("Open log",null,(s,e)=>{if(File.Exists(Log))Process.Start("notepad.exe",Log);}); m.Items.Add("Exit",null,(s,e)=>ExitAll()); return m;}
 Icon MakeIcon(Color color){Bitmap bmp=new Bitmap(16,16); using(Graphics g=Graphics.FromImage(bmp)){g.Clear(Color.Transparent); using(Brush b=new SolidBrush(color))g.FillEllipse(b,1,1,14,14); using(Font f=new Font("Arial",8,FontStyle.Bold)) using(Brush w=new SolidBrush(Color.White)) g.DrawString("M",f,w,3,2);} return Icon.FromHandle(bmp.GetHicon());}
 ManagementObject[] FindRunnerProcesses(){using(var searcher=new ManagementObjectSearcher("SELECT ProcessId,CommandLine FROM Win32_Process WHERE Name='powershell.exe'")){return searcher.Get().Cast<ManagementObject>().Where(m=>((string)(m["CommandLine"]??"")).IndexOf("Start-MichAutoClipSync.ps1",StringComparison.OrdinalIgnoreCase)>=0).ToArray();}}
 void EnsureSingleRunner(){var runners=FindRunnerProcesses(); if(runners.Length>1){foreach(var p in runners.OrderByDescending(p=>Convert.ToInt32(p["ProcessId"])).Skip(1))TryKill(Convert.ToInt32(p["ProcessId"])); LogLine("KILLED_DUPLICATE_RUNNERS count="+(runners.Length-1));} runners=FindRunnerProcesses(); if(runners.Length==0)StartRunner(); else runnerPid=Convert.ToInt32(runners[0]["ProcessId"]);}
 void StartRunner(){var psi=new ProcessStartInfo(); psi.FileName=@"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"; psi.Arguments="-STA -ExecutionPolicy Bypass -File \""+Runner+"\""; psi.WorkingDirectory=Root; psi.CreateNoWindow=true; psi.UseShellExecute=false; var p=Process.Start(psi); runnerPid=p.Id; LogLine("RUNNER_START pid="+runnerPid); icon.Icon=MakeIcon(Color.LimeGreen);}
 string HttpGet(string url,int timeoutMs){try{var req=(HttpWebRequest)WebRequest.Create(url); req.Timeout=timeoutMs; req.ReadWriteTimeout=timeoutMs; using(var res=(HttpWebResponse)req.GetResponse()) using(var sr=new StreamReader(res.GetResponseStream()))return sr.ReadToEnd();}catch(Exception ex){return "ERR "+ex.Message;}}
 void RefreshStatus(){string http=HttpGet("http://127.0.0.1:18765/status",2000); bool run=FindRunnerProcesses().Any(); if(run&&http.StartsWith("{")){lastStatus="OK: runner PID "+runnerPid+", Android bridge reachable"; icon.Icon=MakeIcon(Color.LimeGreen);}else{lastStatus="DEGRADED: runner="+run+" bridge="+http; icon.Icon=MakeIcon(Color.Orange);}}
 void ShowStatus(){RefreshStatus(); icon.BalloonTipTitle="MichAutoClipSync"; icon.BalloonTipText=lastStatus; icon.ShowBalloonTip(4000);} void KillRunners(){foreach(var p in FindRunnerProcesses())TryKill(Convert.ToInt32(p["ProcessId"])); runnerPid=0;} void TryKill(int pid){try{Process.GetProcessById(pid).Kill();LogLine("KILL pid="+pid);}catch{}} void LogLine(string s){try{File.AppendAllText(Log,DateTime.Now.ToString("o")+" "+s+Environment.NewLine,Encoding.UTF8);}catch{}} void ExitAll(){timer.Stop();icon.Visible=false;icon.Dispose();KillRunners();Application.Exit();}
}
}
