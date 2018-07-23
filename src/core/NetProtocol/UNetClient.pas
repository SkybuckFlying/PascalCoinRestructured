unit UNetClient;

interface

uses
  UNetConnection, UNetClientThread;

type
  TNetClient = Class(TNetConnection)
  private
    FNetClientThread : TNetClientThread;
    Procedure OnNetClientThreadTerminated(Sender : TObject);
  public
    Constructor Create(AOwner : TComponent); override;
    Destructor Destroy; override;
  End;

implementation

{ TNetClient }

constructor TNetClient.Create(AOwner: TComponent);
begin
  inherited;
  FNetClientThread := TNetClientThread.Create(Self,OnNetClientThreadTerminated);
  FNetClientThread.FreeOnTerminate := false;
end;

destructor TNetClient.Destroy;
begin
  TLog.NewLog(ltdebug,Classname,'Starting TNetClient.Destroy');
  FNetClientThread.OnTerminate := Nil;
  if Not FNetClientThread.Terminated then begin
    FNetClientThread.Terminate;
    FNetClientThread.WaitFor;
  end;
  FreeAndNil(FNetClientThread);
  inherited;
end;

procedure TNetClient.OnNetClientThreadTerminated(Sender: TObject);
begin
  // Close connection
  if TNetData.NetData.ConnectionExistsAndActive(Self) then begin
    Connected := false;
  end;
end;


end.
