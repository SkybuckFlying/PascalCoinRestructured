unit UNetDataNotifyEventsThread;

interface

type
  { TNetDataNotifyEventsThread ensures that notifications of TNetData object
    will be in main Thread calling a Synchronized method }
  TNetDataNotifyEventsThread = Class(TPCThread)
  private
    FNetData: TNetData;
    FNotifyOnReceivedHelloMessage : Boolean;
    FNotifyOnStatisticsChanged : Boolean;
    FNotifyOnNetConnectionsUpdated : Boolean;
    FNotifyOnNodeServersUpdated : Boolean;
    FNotifyOnBlackListUpdated : Boolean;
  protected
    procedure SynchronizedNotify;
    procedure BCExecute; override;
  public
    Constructor Create(ANetData : TNetData);
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

constructor TNetDataNotifyEventsThread.Create(ANetData: TNetData);
begin
  FNetData := ANetData;
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
  if Not Assigned(FNetData) then exit;

  if FNotifyOnReceivedHelloMessage then begin
    FNotifyOnReceivedHelloMessage := false;
    If Assigned(FNetData.FOnReceivedHelloMessage) then FNetData.FOnReceivedHelloMessage(FNetData);
  end;
  if FNotifyOnStatisticsChanged then begin
    FNotifyOnStatisticsChanged := false;
    If Assigned(FNetData.FOnStatisticsChanged) then FNetData.FOnStatisticsChanged(FNetData);
  end;
  if FNotifyOnNetConnectionsUpdated then begin
    FNotifyOnNetConnectionsUpdated := false;
    If Assigned(FNetData.FOnNetConnectionsUpdated) then FNetData.FOnNetConnectionsUpdated(FNetData);
  end;
  if FNotifyOnNodeServersUpdated then begin
    FNotifyOnNodeServersUpdated := false;
    If Assigned(FNetData.FOnNodeServersUpdated) then FNetData.FOnNodeServersUpdated(FNetData);
  end;
  if FNotifyOnBlackListUpdated then begin
    FNotifyOnBlackListUpdated := false;
    If Assigned(FNetData.FOnBlackListUpdated) then FNetData.FOnBlackListUpdated(FNetData);
  end;
end;




end.
