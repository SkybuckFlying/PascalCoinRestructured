unit UThreadDiscoverConnection;

interface

uses
  UThread, UNodeServerAddress, Classes;

type
  TThreadDiscoverConnection = Class(TPCThread)
    FNodeServerAddress : TNodeServerAddress;
  protected
    procedure BCExecute; override;
  public
    Constructor Create(NodeServerAddress: TNodeServerAddress; NotifyOnTerminate : TNotifyEvent);
  End;

implementation

uses
  UNetClient, ULog, SysUtils, UNetData;

{ TThreadDiscoverConnection }

procedure TThreadDiscoverConnection.BCExecute;
Var NC : TNetClient;
  ok : Boolean;
  ns : TNodeServerAddress;
begin
  Repeat // Face to face conflict when 2 nodes connecting together
    Sleep(Random(1000));
  until (Terminated) Or (Random(5)=0);
  if Terminated then exit;
  TLog.NewLog(ltInfo,Classname,'Starting discovery of connection '+FNodeServerAddress.ip+':'+InttoStr(FNodeServerAddress.port));
  DebugStep := 'Locking list';
  // Register attempt
  If TNetData.NetData.NodeServersAddresses.GetNodeServerAddress(FNodeServerAddress.ip,FNodeServerAddress.port,true,ns) then begin
    ns.last_attempt_to_connect := Now;
    inc(ns.total_failed_attemps_to_connect);
    TNetData.NetData.NodeServersAddresses.SetNodeServerAddress(ns);
  end;
  DebugStep := 'Synchronizing notify';
  if Terminated then exit;
  TNetData.NetData.NotifyNodeServersUpdated;
  // Try to connect
  ok := false;
  DebugStep := 'Trying to connect';
  if Terminated then exit;
  NC := TNetClient.Create(Nil);
  Try
    DebugStep := 'Connecting';
    If NC.ConnectTo(FNodeServerAddress.ip,FNodeServerAddress.port) then begin
      if Terminated then exit;
      Sleep(500);
      DebugStep := 'Is connected now?';
      if Terminated then exit;
      ok :=NC.Connected;
    end;
    if Terminated then exit;
  Finally
    if (not ok) And (Not Terminated) then begin
      DebugStep := 'Destroying non connected';
      NC.FinalizeConnection;
    end;
  End;
  DebugStep := 'Synchronizing notify final';
  if Terminated then exit;
  TNetData.NetData.NotifyNodeServersUpdated;
end;

constructor TThreadDiscoverConnection.Create(NodeServerAddress: TNodeServerAddress; NotifyOnTerminate : TNotifyEvent);
begin
  FNodeServerAddress := NodeServerAddress;
  inherited Create(true);
  OnTerminate := NotifyOnTerminate;
  FreeOnTerminate := true;
  Suspended := false;
end;


end.
