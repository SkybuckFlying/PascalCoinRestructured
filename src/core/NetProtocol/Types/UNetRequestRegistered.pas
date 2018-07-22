unit UNetRequestRegistered;

interface

uses
  UNetConnection;

type
  TNetRequestRegistered = Record
    NetClient : TNetConnection;
    Operation : Word;
    RequestId : Cardinal;
    SendTime : TDateTime;
  end;


implementation

end.
