unit UNetClientThread;

interface

uses
  UThread, UNetClient;  // problem, circular unit reference 7, performing git commit.

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

end.
