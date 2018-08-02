unit UNetClient;

interface

uses
  UNetConnection, UThread, Classes;

type
  TNetClient = Class(TNetConnection)
  private
    FThread : TPCCustomThread;

  protected
    procedure Thread( Sender : TObject );
  public
    Constructor Create;
    Destructor Destroy; override;

    procedure OnTerminated(Sender: TObject);
  End;

implementation

uses
  ULog, SysUtils, UNetData;

{ TNetClient }

constructor TNetClient.Create;
begin
  inherited;
  FThread := TPCCustomThread.Create(Thread);
  FThread.OnTerminate := OnTerminated;
  FThread.FreeOnTerminate := false;
end;

destructor TNetClient.Destroy;
begin
  TLog.NewLog(ltdebug,Classname,'Starting TNetClient.Destroy');
  FThread.OnTerminate := Nil;
  if Not FThread.Terminated then begin
    FThread.Terminate;
    FThread.WaitFor;
  end;
  FreeAndNil(FThread);
  inherited;
end;

procedure TNetClient.Thread( Sender : TObject );
begin
  while (Not FThread.Terminated) do begin
    If Connected then begin
      DoProcessBuffer;
    end;
    Sleep(1);
  end;
  // Close connection
  if PascalNetData.ConnectionExistsAndActive(Self) then begin
    Connected := false;
  end;
end;

procedure TNetClient.OnTerminated(Sender: TObject);
begin
  // Close connection
  if PascalNetData.ConnectionExistsAndActive(Self) then begin
    Connected := false;
  end;
end;


end.
