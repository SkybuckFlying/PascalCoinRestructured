unit UNetDataNotifyEventsThread;

interface

uses
  UThread, Classes; // more circular references problems. "circular reference problem 2" going to commit changes so far.

type
  { TNetDataNotifyEventsThread ensures that notifications of TNetData object
    will be in main Thread calling a Synchronized method }
  TNetDataNotifyEventsThread = Class(TPCThread)
  private
    FNotifyOnReceivedHelloMessage : Boolean;
    FNotifyOnStatisticsChanged : Boolean;
    FNotifyOnNetConnectionsUpdated : Boolean;
    FNotifyOnNodeServersUpdated : Boolean;
    FNotifyOnBlackListUpdated : Boolean;

    FOnReceivedHelloMessage: TNotifyEvent;
    FOnStatisticsChanged: TNotifyEvent;
    FOnNetConnectionsUpdated: TNotifyEvent;
    FOnNodeServersUpdated: TNotifyEvent;
    FOnBlackListUpdated: TNotifyEvent;

  protected
    procedure SynchronizedNotify;
    procedure BCExecute; override;
  public
    Constructor Create;
  End;

implementation

{ TNetDataNotifyEventsThread }

procedure TNetDataNotifyEventsThread.BCExecute;
begin
  while (not Terminated) do begin
    if (FNotifyOnReceivedHelloMessage) Or
       (FNotifyOnStatisticsChanged) Or
       (FNotifyOnNetConnectionsUpdated) Or
       (FNotifyOnNodeServersUpdated) Or
       (FNotifyOnBlackListUpdated) then begin
      Synchronize(SynchronizedNotify);
    end;
    Sleep(10);
  end;
end;

constructor TNetDataNotifyEventsThread.Create;
begin
  FNotifyOnReceivedHelloMessage := false;
  FNotifyOnStatisticsChanged := false;
  FNotifyOnNetConnectionsUpdated := false;
  FNotifyOnNodeServersUpdated := false;
  FNotifyOnBlackListUpdated := false;
  inherited Create(false);
end;

procedure TNetDataNotifyEventsThread.SynchronizedNotify;
begin
  if Terminated then exit;

  // nil/sender used to be FNetData, probably not thread-safe to pass that anyway ;)
  if FNotifyOnReceivedHelloMessage then begin
    FNotifyOnReceivedHelloMessage := false;
    If Assigned(FOnReceivedHelloMessage) then FOnReceivedHelloMessage(nil);
  end;
  if FNotifyOnStatisticsChanged then begin
    FNotifyOnStatisticsChanged := false;
    If Assigned(FOnStatisticsChanged) then FOnStatisticsChanged(nil);
  end;
  if FNotifyOnNetConnectionsUpdated then begin
    FNotifyOnNetConnectionsUpdated := false;
    If Assigned(FOnNetConnectionsUpdated) then FOnNetConnectionsUpdated(nil);
  end;
  if FNotifyOnNodeServersUpdated then begin
    FNotifyOnNodeServersUpdated := false;
    If Assigned(FOnNodeServersUpdated) then FOnNodeServersUpdated(nil);
  end;
  if FNotifyOnBlackListUpdated then begin
    FNotifyOnBlackListUpdated := false;
    If Assigned(FOnBlackListUpdated) then FOnBlackListUpdated(nil);
  end;
end;




end.
