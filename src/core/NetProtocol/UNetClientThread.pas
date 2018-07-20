unit UNetClientThread;

interface

type
  TNetClientThread = Class(TPCThread)
  private
    FNetClient : TNetClient;
  protected
    procedure BCExecute; override;
  public
    Constructor Create(NetClient : TNetClient; AOnTerminateThread : TNotifyEvent);
  End;


implementation

{ TNetClientThread }

procedure TNetClientThread.BCExecute;
begin
  while (Not Terminated) do begin
    If FNetClient.Connected then begin
      FNetClient.DoProcessBuffer;
    end;
    Sleep(1);
  end;
end;

constructor TNetClientThread.Create(NetClient: TNetClient; AOnTerminateThread : TNotifyEvent);
begin
  FNetClient := NetClient;
  inherited Create(false);
  OnTerminate := AOnTerminateThread;
end;

end.
