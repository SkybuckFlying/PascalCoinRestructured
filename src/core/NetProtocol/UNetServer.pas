unit UNetServer;

interface

uses
  UTCPIP, UConst;

type
  { TNetServer }
  TNetServer = Class(TNetTcpIpServer)
  private
  protected
    Procedure OnNewIncommingConnection(Sender : TObject; Client : TNetTcpIpClient); override;
    procedure SetActive(const Value: Boolean); override;
    procedure SetMaxConnections(AValue: Integer); override;
  public
    Constructor Create; override;
  End;

implementation

uses
  UNetServerClient;

{ TNetServer }

constructor TNetServer.Create;
begin
  inherited;
  MaxConnections := CT_MaxClientsConnected;
  NetTcpIpClientClass := TBufferedNetTcpIpClient;
  Port := CT_NetServer_Port;
end;

procedure TNetServer.OnNewIncommingConnection(Sender : TObject; Client : TNetTcpIpClient);
Var n : TNetServerClient;
  DebugStep : String;
  tc : TTickCount;
begin
  DebugStep := '';
  Try
    if Not Client.Connected then exit;
    // NOTE: I'm in a separate thread
    // While in this function the ClientSocket connection will be active, when finishes the ClientSocket will be destroyed
    TLog.NewLog(ltInfo,Classname,'Starting ClientSocket accept '+Client.ClientRemoteAddr);
    n := TNetServerClient.Create(Nil);
    Try
      DebugStep := 'Assigning client';
      n.SetClient(Client);
      TNetData.NetData.IncStatistics(1,1,0,0,0,0);
      TNetData.NetData.NodeServersAddresses.CleanBlackList(False);
      DebugStep := 'Checking blacklisted';
      if (TNetData.NetData.NodeServersAddresses.IsBlackListed(Client.RemoteHost)) then begin
        // Invalid!
        TLog.NewLog(ltinfo,Classname,'Refusing Blacklist ip: '+Client.ClientRemoteAddr);
        n.SendError(ntp_autosend,CT_NetOp_Error, 0,CT_NetError_IPBlackListed,'Your IP is blacklisted:'+Client.ClientRemoteAddr);
        // Wait some time before close connection
        sleep(5000);
      end else begin
        DebugStep := 'Processing buffer and sleep...';
        while (n.Connected) And (Active) do begin
          n.DoProcessBuffer;
          Sleep(10);
        end;
      end;
    Finally
      Try
        TLog.NewLog(ltdebug,Classname,'Finalizing ServerAccept '+IntToHex(PtrInt(n),8)+' '+n.ClientRemoteAddr);
        DebugStep := 'Disconnecting NetServerClient';
        n.Connected := false;
        tc := TPlatform.GetTickCount;
        Repeat
          sleep(10); // 1.5.4 -> To prevent that not client disconnected (and not called OnDisconnect), increase sleep time
        Until (Not n.Connected) Or (tc + 5000 < TPlatform.GetTickCount);
        sleep(5);
        DebugStep := 'Assigning old client';
        n.SetClient( NetTcpIpClientClass.Create(Nil) );
        sleep(500); // Delay - Sleep time before destroying (1.5.3)
        DebugStep := 'Freeing NetServerClient';
      Finally
        n.Free;
      End;
    End;
  Except
    On E:Exception do begin
      TLog.NewLog(lterror,ClassName,'Exception processing client thread at step: '+DebugStep+' - ('+E.ClassName+') '+E.Message);
    end;
  End;
end;

procedure TNetServer.SetActive(const Value: Boolean);
begin
  if Value then begin
    TLog.NewLog(ltinfo,Classname,'Activating server on port '+IntToStr(Port));
  end else begin
    TLog.NewLog(ltinfo,Classname,'Closing server');
  end;
  inherited;
  if Active then begin
    // TNode.Node.AutoDiscoverNodes(CT_Discover_IPs);
  end else if TNetData.NetDataExists then begin
    TNetData.NetData.DisconnectClients;
  end;
end;

procedure TNetServer.SetMaxConnections(AValue: Integer);
begin
  inherited SetMaxConnections(AValue);
  TNetData.NetData.FMaxConnections:=AValue;
end;


end.
