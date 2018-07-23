unit UNetClientsDestroyThread;

interface

uses
  UNetData;   // circular unit reference problem 6, performing git commit.

type
  TNetClientsDestroyThread = Class(TPCThread)
  private
    FNetData : TNetData;
    FTerminatedAllConnections : Boolean;
  protected
    procedure BCExecute; override;
  public
    Constructor Create(NetData : TNetData);
    Procedure WaitForTerminatedAllConnections;
  End;

implementation

{ TNetClientsDestroyThread }

procedure TNetClientsDestroyThread.BCExecute;
Var l,l_to_del : TList;
  i : Integer;
begin
  l_to_del := TList.Create;
  Try
    while not Terminated do begin
      l_to_del.Clear;
      l := FNetData.NetConnections.LockList;
      try
        FTerminatedAllConnections := l.Count=0;
        for i := 0 to l.Count-1 do begin
          If (TObject(l[i]) is TNetClient) And (not TNetConnection(l[i]).Connected)
            And (TNetConnection(l[i]).FDoFinalizeConnection)
            And (Not TNetConnection(l[i]).IsConnecting) then begin
            l_to_del.Add(l[i]);
          end;
        end;
      finally
        FNetData.NetConnections.UnlockList;
      end;
      sleep(500); // Delay - Sleep time before destroying (1.5.3)
      if l_to_del.Count>0 then begin
        TLog.NewLog(ltDebug,ClassName,'Destroying NetClients: '+inttostr(l_to_del.Count));
        for i := 0 to l_to_del.Count - 1 do begin
          Try
            DebugStep := 'Destroying NetClient '+TNetConnection(l_to_del[i]).ClientRemoteAddr;
            TNetConnection(l_to_del[i]).Free;
          Except
            On E:Exception do begin
              TLog.NewLog(ltError,ClassName,'Exception destroying TNetConnection '+IntToHex(PtrInt(l_to_del[i]),8)+': ('+E.ClassName+') '+E.Message );
            end;
          End;
        end;
      end;
      Sleep(100);
    end;
  Finally
    l_to_del.Free;
  end;
end;

constructor TNetClientsDestroyThread.Create(NetData: TNetData);
begin
  FNetData:=NetData;
  FTerminatedAllConnections := true;
  Inherited Create(false);
end;

procedure TNetClientsDestroyThread.WaitForTerminatedAllConnections;
begin
  while (Not FTerminatedAllConnections) do begin
    TLog.NewLog(ltdebug,ClassName,'Waiting all connections terminated');
    Sleep(100);
  end;
end;


end.
