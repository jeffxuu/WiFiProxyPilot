using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public sealed class ProbeServer : IDisposable {
    readonly TcpListener listener;
    readonly Thread worker;
    public int Port { get; private set; }
    public string Request { get; private set; }
    public ProbeServer(string response) {
        listener=new TcpListener(IPAddress.Loopback,0); listener.Start();
        Port=((IPEndPoint)listener.LocalEndpoint).Port;
        worker=new Thread(delegate() {
            try {
                using(var client=listener.AcceptTcpClient()) {
                    var stream=client.GetStream(); stream.ReadTimeout=2000;
                    if(response!=null) {
                        var buffer=new byte[4096]; int count=stream.Read(buffer,0,buffer.Length);
                        Request=Encoding.ASCII.GetString(buffer,0,count);
                        var bytes=Encoding.ASCII.GetBytes(response); stream.Write(bytes,0,bytes.Length);
                    }
                }
            } catch(SocketException) {} catch(System.IO.IOException) {} catch(ObjectDisposedException) {}
        }); worker.IsBackground=true; worker.Start();
    }
    public void Dispose() { listener.Stop(); worker.Join(3000); }
}
