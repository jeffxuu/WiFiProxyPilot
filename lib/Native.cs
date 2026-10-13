using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WiFiProxy {
    public sealed class WifiLink { public string Guid; public string SSID; public string SsidHex; public bool NameDecoded; }
    public sealed class ProxyState { public bool Enable; public string Server; public string Bypass; public string Pac; public uint Flags; }
    public sealed class Native : IDisposable {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct InterfaceInfo { public Guid Guid; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Description; public int State; }
        [StructLayout(LayoutKind.Sequential)]
        struct Ssid { public uint Length; [MarshalAs(UnmanagedType.ByValArray, SizeConst=32)] public byte[] Bytes; }
        [StructLayout(LayoutKind.Sequential)]
        struct Association { public Ssid Ssid; public int BssType; [MarshalAs(UnmanagedType.ByValArray,SizeConst=6)] public byte[] Bssid; public int Phy; public uint PhyIndex; public uint Signal; public uint Rx; public uint Tx; }
        [StructLayout(LayoutKind.Sequential)]
        struct Security { public int Enabled; public int OneX; public int Auth; public int Cipher; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct Connection { public int State; public int Mode; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] public string Profile; public Association Association; public Security Security; }
        [StructLayout(LayoutKind.Sequential)]
        struct Option { public uint Id; public IntPtr Value; }
        [StructLayout(LayoutKind.Sequential)]
        struct OptionList { public uint Size; public IntPtr Connection; public uint Count; public uint Error; public IntPtr Options; }
        delegate void Notification(IntPtr data, IntPtr context);
        [DllImport("wlanapi.dll")] static extern uint WlanOpenHandle(uint version,IntPtr reserved,out uint negotiated,out IntPtr handle);
        [DllImport("wlanapi.dll")] static extern uint WlanCloseHandle(IntPtr handle,IntPtr reserved);
        [DllImport("wlanapi.dll")] static extern uint WlanEnumInterfaces(IntPtr handle,IntPtr reserved,out IntPtr list);
        [DllImport("wlanapi.dll")] static extern uint WlanQueryInterface(IntPtr handle,ref Guid guid,int opcode,IntPtr reserved,out uint size,out IntPtr data,out int type);
        [DllImport("wlanapi.dll")] static extern void WlanFreeMemory(IntPtr memory);
        [DllImport("wlanapi.dll")] static extern uint WlanRegisterNotification(IntPtr handle,uint source,bool ignoreDuplicate,Notification callback,IntPtr context,IntPtr reserved,out uint previous);
        [DllImport("wininet.dll",EntryPoint="InternetQueryOptionW",SetLastError=true)] static extern bool Query(IntPtr h,uint option,ref OptionList list,ref uint size);
        [DllImport("wininet.dll",EntryPoint="InternetSetOptionW",SetLastError=true)] static extern bool Set(IntPtr h,uint option,ref OptionList list,uint size);
        [DllImport("wininet.dll",EntryPoint="InternetSetOptionW",SetLastError=true)] static extern bool Notify(IntPtr h,uint option,IntPtr value,uint size);
        [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr value);
        IntPtr handle;
        Notification callback;
        readonly AutoResetEvent changed = new AutoResetEvent(false);
        long generation;
        public long Generation { get { return Interlocked.Read(ref generation); } }
        public uint NotificationError { get; private set; }
        public Native() {
            uint version; Check(WlanOpenHandle(2,IntPtr.Zero,out version,out handle),"WlanOpenHandle");
            try {
                callback = delegate(IntPtr data,IntPtr context) {
                    // Ignore scan-only notifications; they do not invalidate a connected route snapshot.
                    int code=data==IntPtr.Zero ? 0 : Marshal.ReadInt32(data,4);
                    if(code!=7 && code!=8) SignalChange();
                };
                uint previous;
                // ACM is sufficient for connect/disconnect; avoid MSM's extra location-capability requirement.
                NotificationError=WlanRegisterNotification(handle,0x00000008,true,callback,IntPtr.Zero,IntPtr.Zero,out previous);
                NetworkChange.NetworkAddressChanged += AddressChanged;
                NetworkChange.NetworkAvailabilityChanged += AvailabilityChanged;
            } catch { Dispose(); throw; }
        }
        void SignalChange() { Interlocked.Increment(ref generation); try { changed.Set(); } catch(ObjectDisposedException) {} }
        void AddressChanged(object sender,EventArgs e) { SignalChange(); }
        void AvailabilityChanged(object sender,NetworkAvailabilityEventArgs e) { SignalChange(); }
        static void Check(uint error,string api) { if(error!=0) throw new Win32Exception((int)error,api+" 失败 ("+error+")"); }
        public bool Wait(int milliseconds) { return changed.WaitOne(milliseconds); }
        public static WifiLink DecodeSsid(Guid guid,byte[] bytes,uint length) {
            if(bytes==null || length==0 || length>32 || length>bytes.Length) throw new InvalidOperationException("SSID 长度无效");
            string hex=BitConverter.ToString(bytes,0,(int)length).Replace("-","");
            var link=new WifiLink { Guid=guid.ToString("D"),SsidHex=hex,NameDecoded=true };
            try { link.SSID=new UTF8Encoding(false,true).GetString(bytes,0,(int)length); }
            catch(DecoderFallbackException) { link.NameDecoded=false; link.SSID="[raw SSID "+hex+"]"; }
            return link;
        }
        public WifiLink[] ReadWifi() {
            IntPtr list; Check(WlanEnumInterfaces(handle,IntPtr.Zero,out list),"WlanEnumInterfaces");
            var result=new List<WifiLink>();
            try {
                int count=Marshal.ReadInt32(list); int stride=Marshal.SizeOf(typeof(InterfaceInfo));
                if(count<0 || count>256) throw new InvalidOperationException("WLAN 接口数量异常");
                for(int i=0;i<count;i++) {
                    var item=(InterfaceInfo)Marshal.PtrToStructure(IntPtr.Add(list,8+i*stride),typeof(InterfaceInfo));
                    // wlan_interface_state_disconnected=4; not_ready=0. Transitional states are NOT a confirmed disconnection.
                    if(item.State==4 || item.State==0) continue;
                    if(item.State!=1) throw new InvalidOperationException("Wi-Fi 正在切换，稍后重试");
                    uint size; IntPtr data; int type;
                    Check(WlanQueryInterface(handle,ref item.Guid,7,IntPtr.Zero,out size,out data,out type),"WlanQueryInterface/SSID (检查 Windows 位置权限)");
                    try {
                        if(size<Marshal.SizeOf(typeof(Connection))) throw new InvalidOperationException("WLAN 连接数据不完整");
                        var conn=(Connection)Marshal.PtrToStructure(data,typeof(Connection));
                        if(conn.State!=1 || conn.Association.Ssid.Length==0 || conn.Association.Ssid.Length>32) throw new InvalidOperationException("SSID 暂时不可读取");
                        // The profile field is deliberately unused. SSID bytes are authoritative.
                        result.Add(DecodeSsid(item.Guid,conn.Association.Ssid.Bytes,conn.Association.Ssid.Length));
                    } finally { WlanFreeMemory(data); }
                }
                return result.ToArray();
            } finally { WlanFreeMemory(list); }
        }
        static IntPtr AllocateOptions(uint[] ids,out OptionList list) {
            int stride=Marshal.SizeOf(typeof(Option)); IntPtr ptr=Marshal.AllocHGlobal(stride*ids.Length);
            for(int i=0;i<ids.Length;i++) Marshal.StructureToPtr(new Option { Id=ids[i],Value=IntPtr.Zero },IntPtr.Add(ptr,i*stride),false);
            list=new OptionList { Size=(uint)Marshal.SizeOf(typeof(OptionList)),Count=(uint)ids.Length,Options=ptr };
            return ptr;
        }
        public static ProxyState ReadProxy() {
            // FLAGS_UI preserves the user's autodetect selection even if WPAD failed on this network.
            OptionList list; IntPtr ptr=AllocateOptions(new uint[] {10,2,3,4},out list); uint size=list.Size;
            try {
                if(!Query(IntPtr.Zero,75,ref list,ref size)) throw new Win32Exception(Marshal.GetLastWin32Error(),"InternetQueryOption 失败");
                int stride=Marshal.SizeOf(typeof(Option)); var values=new Option[4];
                for(int i=0;i<4;i++) values[i]=(Option)Marshal.PtrToStructure(IntPtr.Add(ptr,i*stride),typeof(Option));
                uint flags=unchecked((uint)values[0].Value.ToInt64());
                return new ProxyState { Flags=flags,Enable=(flags&2)!=0,Server=Marshal.PtrToStringUni(values[1].Value)??"",Bypass=Marshal.PtrToStringUni(values[2].Value)??"",Pac=Marshal.PtrToStringUni(values[3].Value)??"" };
            } finally {
                for(int i=1;i<4;i++) { var opt=(Option)Marshal.PtrToStructure(IntPtr.Add(ptr,i*Marshal.SizeOf(typeof(Option))),typeof(Option)); if(opt.Value!=IntPtr.Zero) GlobalFree(opt.Value); }
                Marshal.FreeHGlobal(ptr);
            }
        }
        public static void Refresh() {
            if(!Notify(IntPtr.Zero,39,IntPtr.Zero,0)) throw new Win32Exception(Marshal.GetLastWin32Error(),"代理变更通知失败");
            if(!Notify(IntPtr.Zero,37,IntPtr.Zero,0)) throw new Win32Exception(Marshal.GetLastWin32Error(),"代理刷新失败");
        }
        public static void SetManual(bool enable,string server,string bypass) {
            var old=ReadProxy(); uint flags=old.Flags;
            flags=enable ? (flags|3u) : ((flags&~2u)|1u); // Preserve PAC/autodetect and unrelated flags.
            OptionList list; IntPtr ptr=AllocateOptions(new uint[] {1,2,3},out list);
            IntPtr s=Marshal.StringToHGlobalUni(server??""); IntPtr b=Marshal.StringToHGlobalUni(bypass??"");
            try {
                int stride=Marshal.SizeOf(typeof(Option));
                Marshal.StructureToPtr(new Option { Id=1,Value=new IntPtr(flags) },ptr,false);
                Marshal.StructureToPtr(new Option { Id=2,Value=s },IntPtr.Add(ptr,stride),false);
                Marshal.StructureToPtr(new Option { Id=3,Value=b },IntPtr.Add(ptr,2*stride),false);
                if(!Set(IntPtr.Zero,75,ref list,list.Size)) throw new Win32Exception(Marshal.GetLastWin32Error(),"InternetSetOption 失败");
                Refresh();
                var actual=ReadProxy();
                if(actual.Enable!=enable || actual.Server!=(server??"") || actual.Bypass!=(bypass??"") || (actual.Flags&12)!=(old.Flags&12) || actual.Pac!=old.Pac) throw new InvalidOperationException("WinINet 回读不一致或 PAC 被改变");
            } finally { Marshal.FreeHGlobal(s); Marshal.FreeHGlobal(b); Marshal.FreeHGlobal(ptr); }
        }
        public void Dispose() {
            NetworkChange.NetworkAddressChanged -= AddressChanged;
            NetworkChange.NetworkAvailabilityChanged -= AvailabilityChanged;
            if(handle!=IntPtr.Zero) { uint previous; WlanRegisterNotification(handle,0,true,null,IntPtr.Zero,IntPtr.Zero,out previous); WlanCloseHandle(handle,IntPtr.Zero); handle=IntPtr.Zero; }
            changed.Dispose(); GC.KeepAlive(callback);
        }
    }
}
